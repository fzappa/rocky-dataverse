#!/usr/bin/env bash
#
# Install Dataverse on Rocky Linux
#
# Alan Franco
# github.com/fzappa/rocky-dataverse
#
# License: GPL-3.0
#
# Based on https://guides.dataverse.org/en/5.10/installation/prerequisites.html
#

####### CHANGE ME ##########
INSTITUTE="My Institute"
EMAIL="user@domain.org"
PROJECT_NAME="RedeDadosAbertos"
SCRIPT_DIR="/opt/rocky-dataverse"
DATAVERSE_VERSION="5.10"
JAVA_VERSION="11"
POSTGRESQL_VERSION="13"


# DOI CONFIGURE
USE_FAKE_DOI="YES"

# EDIT IF USE_FAKE_DOI="NO"
DOI_PREFIX="10.5072"
DOI_USERNAME="username"
DOI_PASSWD="password"

BUILD_IMAGEMAGICK="YES"
BUILD_R="YES"
CHANGE_PAYARA_INDEX="NO"

# CUSTOM HEADER, FOOTER AND HOMEPAGE
CUSTOM_PAGES="NO"


# If you want to install Maxmind
# Create an account and download at: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data?lang=en
BUILD_MAXMIND="NO"
GEOLITE_PACKAGE="GeoLite2-Country.tar.gz"


# Change according to version
# FIXME ==>
if [[ $DATAVERSE_VERSION == "5.10" || $DATAVERSE_VERSION == "5.9" || $DATAVERSE_VERSION == "5.8" || $DATAVERSE_VERSION == "5.7" || $DATAVERSE_VERSION == "5.6" ]]; then
    # v5.10, v5.9, v5.8. v5.7, v5.6
    PAYARA_VERSION="5.2021.5"
elif [[ $DATAVERSE_VERSION == "5.5" ]]; then
    # v5.5
    PAYARA_VERSION="5.2020.6" 
else
    echo -e "${RED}ERROR: Dataverse $DATAVERSE_VERSION is not supported.${NC}"
    exit
fi

if [[ $DATAVERSE_VERSION == "5.10" ]]; then
	SOLR_VERSION="8.11.1"
else
	SOLR_VERSION="8.8.1"
fi

PAYARA_SERVICE="https://guides.dataverse.org/en/$DATAVERSE_VERSION/_downloads/c08a166c96044c52a1a470cc2ff60444/payara.service"
SOLR_SERVICE="https://guides.dataverse.org/en/$DATAVERSE_VERSION/_downloads/0736976a136678bbc024ce423b223d3a/solr.service"

##############################


# Colours
RED='\e[0;31m'
REDB='\e[1;31;5m'
GREEN='\e[1;92m'
YELLOW='\e[1;33m'
NC='\e[0m' # No Color


pre_config(){
    echo -e "${YELLOW}Pre config...${NC}"
    read_any
    if [ ! -d $SCRIPT_DIR ]; then
        mkdir $SCRIPT_DIR         
        yes | cp -rp ~/rocky-dataverse.sh $SCRIPT_DIR   
    else
        yes | cp -rp ~/rocky-dataverse.sh $SCRIPT_DIR       
    fi

    if [[ $BUILD_MAXMIND == "YES" ]]; then
        if [ -f ~/$GEOLITE_PACKAGE ]; then
            yes | cp -rp ~/$GEOLITE_PACKAGE $SCRIPT_DIR
        else
            echo -e "${RED}ERROR: $GEOLITE_PACKAGE NOT FOUND in ~/${NC}"
            echo -e "${YELLOW}Please create an account and download at:${NC}" 
            echo -e "${YELLOW}https://dev.maxmind.com/geoip/geolite2-free-geolocation-data?lang=en${NC}"
            echo -e "${YELLOW}or set BUILD_MAXMIND var to NO.${NC}" 
            exit 
        fi
    fi

    if [[ $CHANGE_PAYARA_INDEX == "YES" ]]; then
        if [ -f ~/index.html ]; then
            yes | cp -rp ~/index.html $SCRIPT_DIR
        else
            echo -e "${RED}ERROR: index.html NOT FOUND in ~/${NC}"
        fi
    fi
}


install_java(){
    echo -e "${YELLOW}Install Java $JAVA_VERSION...${NC}"
    read_any
    dnf install -y java-$JAVA_VERSION-openjdk
    alternatives --set java java-$JAVA_VERSION-openjdk.x86_64
}


download_payara(){
    echo -e "${YELLOW}Download Payara $PAYARA_VERSION...${NC}"
    read_any
    useradd dataverse
    usermod -aG sudo dataverse
    
    cd $SCRIPT_DIR
    wget -c https://s3-eu-west-1.amazonaws.com/payara.fish/Payara+Downloads/$PAYARA_VERSION/payara-$PAYARA_VERSION.zip
    unzip payara-$PAYARA_VERSION.zip
    mv payara5 /usr/local
}


install_payara(){  
    echo -e "${YELLOW}Install Payara $PAYARA_VERSION...${NC}"  
    read_any

    chown -R root:root /usr/local/payara5
    chown dataverse /usr/local/payara5/glassfish/lib
    chown -R dataverse:dataverse /usr/local/payara5/glassfish/domains/domain1

    
    cd /usr/lib/systemd/system/
    wget -c $PAYARA_SERVICE
    echo -e "${GREEN}Start and enable Payara service...${NC}"
    systemctl daemon-reload
    systemctl enable --now payara.service
    rm -rf $SCRIPT_DIR/payara-$PAYARA_VERSION.zip
}

change_index_payara(){
    echo -e "${YELLOW}Change Payara's default index page...${NC}"  
    read_any

    # Just to not show payara's default page during dataverse startup
    rm -rf /usr/local/payara5/glassfish/domains/domain1/docroot/index.html
    cp $SCRIPT_DIR/index.html /usr/local/payara5/glassfish/domains/domain1/docroot/
    chown dataverse.dataverse /usr/local/payara5/glassfish/domains/domain1/docroot/index.html
    chmod 755 /usr/local/payara5/glassfish/domains/domain1/docroot/index.html
}


install_postgresql(){
    echo -e "${YELLOW}Install Postgresql $POSTGRESQL_VERSION...${NC}"
    read_any
    #dnf module list postgresql
    dnf module reset postgresql
    dnf module install -y postgresql:$POSTGRESQL_VERSION
    postgresql-setup --initdb
    systemctl enable --now postgresql
}


configure_postgresql(){
    echo -e "${YELLOW}Configure Postgresql $POSTGRESQL_VERSION...${NC}"
    read_any
    # vim /var/lib/pgsql/data/pg_hba.conf
    echo "local    all    all    trust" > /var/lib/pgsql/data/pg_hba.conf
    echo "host     all    all    127.0.0.1/32    trust" >> /var/lib/pgsql/data/pg_hba.conf
    echo "host     all    all    ::1/128         trust" >> /var/lib/pgsql/data/pg_hba.conf
    echo "local   replication     all                              peer" >> /var/lib/pgsql/data/pg_hba.conf
    echo "host    replication     all     127.0.0.1/32            ident" >> /var/lib/pgsql/data/pg_hba.conf
    echo "host    replication     all     ::1/128                 ident" >> /var/lib/pgsql/data/pg_hba.conf


    systemctl restart postgresql
}


download_dataverse(){
    echo -e "${YELLOW}Download Dataverse v$DATAVERSE_VERSION...${NC}"
    read_any
    cd $SCRIPT_DIR
    wget -c https://github.com/IQSS/dataverse/releases/download/v$DATAVERSE_VERSION/dvinstall.zip
    unzip dvinstall.zip
}


install_solr(){
    echo -e "${YELLOW}Install SOLR $SOLR_VERSION...${NC}"
    read_any

    cd $SCRIPT_DIR
    useradd solr
    usermod -aG sudo solr

    mkdir /usr/local/solr
    chown solr:solr /usr/local/solr
    cd /usr/local/solr
    sudo -u solr wget -c https://archive.apache.org/dist/lucene/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz
    sudo -u solr tar xvzf solr-$SOLR_VERSION.tgz
    cd solr-$SOLR_VERSION
    sudo -u solr cp -r /usr/local/solr/solr-$SOLR_VERSION/server/solr/configsets/_default server/solr/collection1
    sudo -u solr cp $SCRIPT_DIR/dvinstall/schema*.xml /usr/local/solr/solr-$SOLR_VERSION/server/solr/collection1/conf
    sudo -u solr cp $SCRIPT_DIR/dvinstall/solrconfig.xml /usr/local/solr/solr-$SOLR_VERSION/server/solr/collection1/conf

    echo "solr soft nproc 65000" >> /etc/security/limits.conf
    echo "solr hard nproc 65000" >> /etc/security/limits.conf
    echo "solr soft nofile 65000" >> /etc/security/limits.conf
    echo "solr hard nofile 65000" >> /etc/security/limits.conf

    dnf install -y lsof

    sudo -u solr echo "name=collection1" > /usr/local/solr/solr-$SOLR_VERSION/server/solr/collection1/core.properties
    sudo -u solr sed -i "s/name=\"solr.jetty.request.header.size\" default=\"8192\"/name=\"solr.jetty.request.header.size\" default=\"102400\"/g" /usr/local/solr/solr-$SOLR_VERSION/server/etc/jetty.xml

    cd /etc/systemd/system
    wget -c $SOLR_SERVICE

    systemctl daemon-reload
    echo -e "${GREEN}Start and enable SOLR service...${NC}"
    systemctl enable --now solr.service
    usermod -s /sbin/nologin solr
    rm -rf /usr/local/solr/solr-$SOLR_VERSION.tgz
}


install_magick(){
    echo -e "${YELLOW}Install ImageMagick...${NC}"
    read_any
    dnf install -y epel-release
    dnf install -y jq
    dnf install -y ImageMagick
}


install_r(){
    echo -e "${YELLOW}Install R...${NC}"
    read_any

    dnf config-manager --enable powertools
    dnf install -y R-core R-core-devel

    mount -o remount,exec /tmp
    Rscript -e 'install.packages("R2HTML", repos="https://cloud.r-project.org/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("rjson", repos="https://cloud.r-project.org/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("DescTools", repos="https://cloud.r-project.org/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("Rserve", repos="https://cloud.r-project.org/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("haven", repos="https://cloud.r-project.org/", lib="/usr/lib64/R/library")'
    mount -o remount,rw,noexec,nosuid,nodev,bind /tmp

    cd $SCRIPT_DIR
    git clone -b master https://github.com/IQSS/dataverse.git
    cd $SCRIPT_DIR/dataverse/scripts/r/rserve
    bash rserve-setup.sh
    systemctl daemon-reload
    systemctl enable --now rserve
    
}

install_maxmind(){
    echo -e "${YELLOW}Install MAXMIND...${NC}"
    read_any

    cd /usr/local
    wget -c https://github.com/CDLUC3/counter-processor/archive/v0.0.1.tar.gz
    tar xvfz v0.0.1.tar.gz

    cd /usr/local/counter-processor-0.0.1

    cd $SCRIPT_DIR
    tar xvfz $GEOLITE_PACKAGE
    cp GeoLite2-Country_*/GeoLite2-Country.mmdb /usr/local/counter-processor-0.0.1/maxmind_geoip

    useradd counter
    chown -R counter:counter /usr/local/counter-processor-0.0.1

    python3 -m ensurepip
    cd /usr/local/counter-processor-0.0.1
    pip3 install -r requirements.txt

}

custom_pages(){
    echo -e "${YELLOW}Configure custom pages for DATAVERSE $DATAVERSE_VERSION...${NC}"
    read_any

    mkdir -p /var/www/dataverse/branding/
    cd /var/www/dataverse/branding
    wget -c https://guides.dataverse.org/en/latest/_downloads/0f28d7fe1a9937d9ef47ae3f8b51403e/custom-homepage.html
    wget -c https://guides.dataverse.org/en/latest/_downloads/4e2c4e359b641142d3b5d34f979248b0/custom-header.html
    wget -c https://guides.dataverse.org/en/latest/_downloads/1c9c782c8c0a4b602ad667eb5871203b/custom-footer.html
    wget -c https://guides.dataverse.org/en/latest/_downloads/483ea011831fc72d7f1e923a1898f3a3/custom-stylesheet.css

    curl -X PUT -d '/var/www/dataverse/branding/custom-homepage.html' http://localhost:8080/api/admin/settings/:HomePageCustomizationFile

    curl -X PUT -d '/var/www/dataverse/branding/custom-header.html' http://localhost:8080/api/admin/settings/:HeaderCustomizationFile
    curl -X PUT -d 'true' http://localhost:8080/api/admin/settings/:DisableRootDataverseTheme

    curl -X PUT -d '/var/www/dataverse/branding/custom-footer.html' http://localhost:8080/api/admin/settings/:FooterCustomizationFile

    curl -X PUT -d '/var/www/dataverse/branding/custom-stylesheet.css' http://localhost:8080/api/admin/settings/:StyleCustomizationFile
}

install_dataverse(){
    echo -e "${YELLOW}Install DATAVERSE $DATAVERSE_VERSION...${NC}"
    read_any
    cd $SCRIPT_DIR/dvinstall/
    dnf install -y python3-psycopg2
    sudo -u dataverse python3 install.py

    # como root
    cd $SCRIPT_DIR/dvinstall/
    bash setup-all.sh

    chown root /usr/local/payara5/glassfish/lib
}

configure_fake_doi(){
    # https://brapci.inf.br/wiki/index.php/Dataverse:DOI
    echo -e "${YELLOW}Configure FAKE DOI for tests...\n${NC}"
    read_any

    curl -X PUT -d FAKE http://localhost:8080/api/admin/settings/:DoiProvider
}

configure_regular_doi(){
    # https://brapci.inf.br/wiki/index.php/Dataverse:DOI
    # https://guides.dataverse.org/en/5327-fake-pid-provider/installation/config.html#id106
    echo -e "${YELLOW}Configure Regular DOI...\n${NC}"
    read_any

    sed -i "s/Ddoi.username=dataciteuser/Ddoi.username=$DOI_USERNAME/g" /usr/local/payara5/glassfish/domains/domain1/config/domain.xml
    sed -i "s/Ddoi.password=\${ALIAS=doi_password_alias}/Ddoi.password=$DOI_PASSWD/g" /usr/local/payara5/glassfish/domains/domain1/config/domain.xml

    curl -X PUT -d "$DOI_PREFIX" localhost:8080/api/admin/settings/:Authority
    curl -X PUT -d DataCite http://localhost:8080/api/admin/settings/:DoiProvider
}

configure_dataverse(){
    echo -e "${YELLOW}Configure DATAVERSE $DATAVERSE_VERSION for tests...\n${NC}"
    read_any

    
    if [[ $USE_FAKE_DOI == "YES" ]]; then
        configure_fake_doi
    else
        configure_regular_doi
    fi
    
    curl -X PUT -d "$PROJECT_NAME <$EMAIL>" http://localhost:8080/api/admin/settings/:SystemEmail
    curl -X PUT -d ", $INSTITUTE" http://localhost:8080/api/admin/settings/:FooterCopyright

}

configure_selinux(){
    echo -e "${YELLOW}Enable AVC rules in SELinux for Apache and NGINX...${NC}"
    read_any

    setsebool -P httpd_can_network_connect 1
    setsebool -P httpd_can_network_relay 1
    setsebool -P httpd_run_stickshift 1
    setsebool -P httpd_setrlimit 1
}

security(){

    # Restore Postgresql security
    sed -i '2s/trust/md5/' /var/lib/pgsql/data/pg_hba.conf

    # enable the following setting to address CVE-2021-44228
    echo "SOLR_OPTS=\"\$SOLR_OPTS -Dlog4j2.formatMsgNoLookups=true\"" >> /usr/local/solr/$SOLR_VERSION/bin/solr.in.sh
}

read_any(){
    read -n 1 -s -r -p "Press any key to continue..."$'\n' msg
}


main(){

    echo -e "${REDB}\n\nINSTALL DATAVERSE v$DATAVERSE_VERSION ${NC}"

    if [[ $EUID -ne 0 ]]; then
        echo -e "${REDB}ERROR: Run the script as ROOT!\n${NC}"
        exit
    else
        pre_config
        install_java
        download_payara
        install_payara
        install_postgresql
        configure_postgresql
        download_dataverse
        install_solr
        if [[ $BUILD_IMAGEMAGICK == "YES" ]]; then
            install_magick
        fi
        if [[ $BUILD_R == "YES" ]]; then
            install_r
        fi
        if [[ $BUILD_MAXMIND == "YES" ]]; then
            install_maxmind
        fi
        install_dataverse
        configure_dataverse
        configure_selinux
        if [[ $CHANGE_PAYARA_INDEX == "YES" ]]; then
            change_index_payara
        fi
        if [[ $CUSTOM_PAGES == "YES" ]]; then
            custom_pages
        fi

        security
    
        echo -e "${REDB}\n\nPOST INSTALL TIPS${NC}"
        echo " "
        echo -e "${GREEN}RECOMENDED: Check SELinux rules with audit2allow -a${NC}"
        echo -e "${GREEN}Create test modules with \"audit2allow -a -M module_name\"${NC}"
        echo -e "${GREEN}Install modules with \"semodule -i module_name.te\"${NC}"
        echo -e "${GREEN}Enable with \"semodule -e module_name\"${NC}"

    fi
}

main


