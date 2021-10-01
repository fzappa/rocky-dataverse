#!/usr/bin/env bash
#
# Install Dataverse on Rocky Linux
#
# Alan Franco
# github.com/fzappa/rocky-dataverse
#
# License: GPL-3.0
#
# Based on https://guides.dataverse.org/en/5.5/installation/prerequisites.html
#

####### CHANGE ME ##########
EMAIL="user@domain.org"
PROJECT_NAME="RedeDadosAbertos"
SCRIPT_DIR="/opt/rocky-dataverse"
DATAVERSE_VERSION="5.5"
#DATAVERSE_VERSION="5.6"
PAYARA_VERSION="5.2020.6" 
#PAYARA_VERSION="5.2021.5" # V5.6
JAVA_VERSION="11"
POSTGRESQL_VERSION="13"
SOLR_VERSION="8.8.1"

# Create an account and download at: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data?lang=en
GEOLITE="GeoLite2-Country_20210921.tar.gz"

# Change according to version
# V5.5 V5.6
PAYARA_SERVICE="https://guides.dataverse.org/en/5.5/_downloads/c08a166c96044c52a1a470cc2ff60444/payara.service"
SOLR_SERVICE="https://guides.dataverse.org/en/5.5/_downloads/0736976a136678bbc024ce423b223d3a/solr.service"
# V5.4.1
# PAYARA_SERVICE="https://guides.dataverse.org/en/5.4.1/_downloads/payara.service"
# SOLR_SERVICE="https://guides.dataverse.org/en/5.4.1/_downloads/solr.service"

##############################


# Colours
RED='\e[0;31m'
REDB='\e[1;31;5m'
GREEN='\e[1;92m'
YELLOW='\e[1;33m'
NC='\e[0m' # No Color


pre_config(){
    echo -e "${YELLOW}Pre config..."
    read -n 1 -s -r -p "Press any key to continue"
    if [ ! -d $SCRIPT_DIR ]; then
        mkdir $SCRIPT_DIR         
        yes | cp -rp ~/datverse_rocky.sh $SCRIPT_DIR        
    fi

    if [ -f ~/$GEOLITE ]; then
        yes | cp -rp ~/$GEOLITE $SCRIPT_DIR
    else
        echo -e "${RED}ERROR: $GEOLITE NOT FOUND in ~/${NC}"
        echo -e "${YELLOW}Please create an account and download at:${NC}" 
        echo -e "${YELLOW}https://dev.maxmind.com/geoip/geolite2-free-geolocation-data?lang=en${NC}"
        exit 
    fi

}


install_java(){
    echo -e "${YELLOW}Install Java $JAVA_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    dnf install -y java-$JAVA_VERSION-openjdk
    alternatives --set java java-$JAVA_VERSION-openjdk.x86_64
}


download_payara(){
    echo -e "${YELLOW}Download Payara $PAYARA_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    useradd dataverse
    usermod -aG sudo dataverse
    
    cd $SCRIPT_DIR
    wget https://s3-eu-west-1.amazonaws.com/payara.fish/Payara+Downloads/$PAYARA_VERSION/payara-$PAYARA_VERSION.zip
    unzip payara-$PAYARA_VERSION.zip
    mv payara5 /usr/local
}


install_payara(){  
    echo -e "${YELLOW}Install Payara $PAYARA_VERSION...${NC}"  
    read -n 1 -s -r -p "Press any key to continue"

    chown -R root:root /usr/local/payara5
    chown dataverse /usr/local/payara5/glassfish/lib
    chown -R dataverse:dataverse /usr/local/payara5/glassfish/domains/domain1

    
    cd /usr/lib/systemd/system/
    wget $PAYARA_SERVICE
    echo -e "${GREEN}Start and enable Payara service...${NC}"
    systemctl daemon-reload
    systemctl enable --now payara.service
}


install_postgresql(){
    echo -e "${YELLOW}Install Postgresql $POSTGRESQL_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    #dnf module list postgresql
    dnf module reset postgresql
    dnf module install -y postgresql:$POSTGRESQL_VERSION
    postgresql-setup --initdb
    systemctl enable --now postgresql
}


configure_postgresql(){
    echo -e "${YELLOW}Configure Postgresql $POSTGRESQL_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
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
    read -n 1 -s -r -p "Press any key to continue"
    cd $SCRIPT_DIR
    wget https://github.com/IQSS/dataverse/releases/download/v$DATAVERSE_VERSION/dvinstall.zip
    unzip dvinstall.zip
}


install_solr(){
    echo -e "${YELLOW}Install SOLR $SOLR_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"

    cd $SCRIPT_DIR
    useradd solr
    usermod -aG sudo solr

    mkdir /usr/local/solr
    chown solr:solr /usr/local/solr
    cd /usr/local/solr
    sudo -u solr wget https://archive.apache.org/dist/lucene/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz
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

    cd /etc/systemd/system
    wget $SOLR_SERVICE

    systemctl daemon-reload
    echo -e "${GREEN}Start and enable SOLR service...${NC}"
    systemctl enable --now solr.service
    usermod -s /sbin/nologin solr
}


install_magick(){
    echo -e "${YELLOW}Install ImageMagick...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    dnf install -y epel-release
    dnf install -y jq
    dnf install -y ImageMagick
}


install_r(){
    echo -e "${YELLOW}Install R...${NC}"
    read -n 1 -s -r -p "Press any key to continue"

    dnf config-manager --enable powertools
    dnf install -y R-core R-core-devel

    mount -o remount,exec /tmp
    Rscript -e 'install.packages("R2HTML", repos="https://cran.fiocruz.br/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("rjson", repos="https://cran.fiocruz.br/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("DescTools", repos="https://cran.fiocruz.br/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("Rserve", repos="https://cran.fiocruz.br/", lib="/usr/lib64/R/library")'
    Rscript -e 'install.packages("haven", repos="https://cran.fiocruz.br/", lib="/usr/lib64/R/library")'
    mount -o remount,noexec /tmp

    cd $SCRIPT_DIR
    git clone -b master https://github.com/IQSS/dataverse.git
    cd $SCRIPT_DIR/dataverse/scripts/r/rserve
    bash rserve-setup.sh
    systemctl daemon-reload
    systemctl enable --now rserve
    
}

install_maxmind(){
    echo -e "${YELLOW}Install MAXMIND...${NC}"
    read -n 1 -s -r -p "Press any key to continue"

    cd /usr/local
    wget https://github.com/CDLUC3/counter-processor/archive/v0.0.1.tar.gz
    tar xvfz v0.0.1.tar.gz

    cd /usr/local/counter-processor-0.0.1

    cd $SCRIPT_DIR
    tar xvfz $GEOLITE
    cp GeoLite2-Country_*/GeoLite2-Country.mmdb /usr/local/counter-processor-0.0.1/maxmind_geoip

    useradd counter
    chown -R counter:counter /usr/local/counter-processor-0.0.1

    python3 -m ensurepip
    cd /usr/local/counter-processor-0.0.1
    pip3 install -r requirements.txt

}


install_dataverse(){
    echo -e "${YELLOW}Install DATAVERSE $DATAVERSE_VERSION...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    cd $SCRIPT_DIR/dvinstall/
    dnf install -y python3-psycopg2
    sudo -u dataverse python3 install.py

    # como root
    cd $SCRIPT_DIR/dvinstall/
    bash setup-all.sh

    chown root /usr/local/payara5/glassfish/lib
}

configure_dataverse(){
    echo -e "${YELLOW}Configure DATAVERSE $DATAVERSE_VERSION for tests...${NC}"
    read -n 1 -s -r -p "Press any key to continue"
    
    curl http://localhost:8080/api/admin/settings/:DoiProvider -X PUT -d FAKE
    curl -X PUT -d '$PROJECT_NAME <$EMAIL>' http://localhost:8080/api/admin/settings/:SystemEmail

}

main(){

    echo -e "${REDB}INSTALL DATAVERSE v$DATAVERSE_VERSION ${NC}"

    if [[ $EUID -ne 0 ]]; then
        echo -e "${REDB}ERROR: Run the script as ROOT!${NC}"
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
        install_magick
        install_r
        install_maxmind
        install_dataverse
        configure_dataverse
    
        echo -e "${REDB}POST INSTALL TIPS${NC}"
        echo -e "${GREEN}CHECK: vim /usr/local/payara5/glassfish/domains/domain1/config/domain.xml${NC}"
        echo -e "${GREEN}CHECK: <jvm-options>-client</jvm-options> to <jvm-options>-server</jvm-options>${NC}"
        echo " "
        echo -e "${GREEN}EDIT: /usr/local/solr/solr-$SOLR_VERSION/server/etc/jetty.xml${NC}"
        echo -e "${GREEN}Increasing requestHeaderSize from 8192 to 102400${NC}"
        echo " "
        echo -e "${GREEN}EDIT SECURITY: In /var/lib/pgsql/data/pg_hba.conf change line to:${NC}"
        echo -e "${GREEN}host     all    all    127.0.0.1/32    md5${NC}"
    fi
}

main


