#!/usr/bin/env bash

set -e

: ${ALICLOUD_ACCESS_KEY_ID:?}
: ${ALICLOUD_SECRET_ACCESS_KEY:?}
: ${ALICLOUD_DEFAULT_REGION:?}
: ${GIT_USER_EMAIL:?}
: ${GIT_USER_NAME:?}
: ${GIT_USER_ID:?}
: ${GIT_USER_PASSWORD:?}
: ${BOSH_REPO_HOST:?}

CURRENT_PATH=$(pwd)
SOURCE_PATH=$CURRENT_PATH/bosh-alicloud-cpi-release
TERRAFORM_PATH=$CURRENT_PATH/terraform
TERRAFORM_MODULE=$SOURCE_PATH/ci/assets/terraform
TERRAFORM_METADATA=$CURRENT_PATH/environment
METADATA=metadata
TERRAFORM_VERSION=0.10.0
TERRAFORM_PROVIDER_VERSION=1.2.10


wget -N https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
wget -N https://github.com/alibaba/terraform-provider/releases/download/V${TERRAFORM_PROVIDER_VERSION}/terraform-provider-alicloud_linux-amd64.tgz

mkdir -p ${TERRAFORM_PATH}

unzip -o terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d ${TERRAFORM_PATH}
tar -xzvf terraform-provider-alicloud_linux-amd64.tgz
mv -f bin/terraform* ${TERRAFORM_PATH}
rm -rf ./bin
export PATH="${TERRAFORM_PATH}:$PATH"

echo "******** git install expect ********"
sudo apt-get install expect -y

echo "******** clone terraform template by https ********"
echo "#!/usr/bin/expect" > git_install.sh
echo "spawn git clone -b ${BOSH_REPO_BRANCH} --single-branch ${BOSH_REPO_HOST}" >> git_install.sh
echo "expect \"Username for 'https://github.com': \"" >> git_install.sh
echo "send \"${GIT_USER_ID}\r\"" >> git_install.sh
echo "expect \"Password for 'https://${GIT_USER_ID}@github.com': \"" >> git_install.sh
echo "send \"${GIT_USER_PASSWORD}\r\"" >> git_install.sh
echo "expect eof" >> git_install.sh
echo exit >> git_install.sh
chmod +x git_install.sh
./git_install.sh
rm -rf ./git_install.sh
echo "******** Clone finished! ********"

cd ${SOURCE_PATH}

echo "******** tell docker who am I ********"
git config --global user.email ${GIT_USER_EMAIL}
git config --global user.name ${GIT_USER_NAME}
git config --local -l

cd ${TERRAFORM_MODULE}

echo -e "\nDestroy terraform environment......"
terraform init
TIMES_COUNT=1
while [[ ${TIMES_COUNT} -le 20 ]];
do
    echo -e "******** Try to destroy environment - ${TIMES_COUNT} times ********\n"
    if [[ $(terraform destroy -var alicloud_access_key=${ALICLOUD_ACCESS_KEY_ID} -var alicloud_secret_key=${ALICLOUD_SECRET_ACCESS_KEY} -var alicloud_region=${ALICLOUD_DEFAULT_REGION} -force) && $? -eq 0 ]] ; then
        echo -e "******* Destroy terraform environment successfully ******* \n"
        break
    else
        ((TIMES_COUNT++))
        if [[ ${TIMES_COUNT} -gt 20 ]]; then
            echo "******** Retry to destroy environment failed. ********"
        else
            echo "Waitting for 5 seconds......********"
            sleep 5
            continue
        fi
    fi
done

if [ -e ${METADATA} ];
then
    echo "" > $METADATA
fi


function copyToOutput(){

    cp -rf $1/. $2

    cd $2

    if [ -e ${METADATA} ]; then
        echo "" > $METADATA
    fi

    ls -la
    echo "******** show git repo info ********"
    git remote -v
    git branch

    echo "******** show git repo info ********"
    git remote -v
    git branch

    git status | sed -n 'p' |while read LINE
    do
        echo "echo LINE: $LINE"
        if [[ $LINE == HEAD*detached* ]];
        then
            echo "****** fix detached branch ******"s
            read -r -a Words <<< $LINE

            git status | sed -n 'p' |while read LI
            do
                echo "echo LI: $LI"
                if [[ $LI == Changes*not*staged*for*commit* ]];
                then
                    git add .
                    git commit -m 'destroy environment commit on detached'
                    git branch temp
                    git checkout ${BOSH_REPO_BRANCH}
                    git merge temp
                    git branch
                    git branch -d temp
                fi
            done
            break
        fi
    done

    echo "******* git status ******"
    git status

    git status | sed -n '$p' |while read LINE
    do
        echo $LINE
        if [[ $LINE != nothing*clean ]];
        then
            echo $LINE
            git add .
            git commit -m 'destroy environment commit -a'
            return 0
        fi
    done

    git status
    return 0
}

echo -e "\nCopy to output ......"
copyToOutput ${SOURCE_PATH} ${TERRAFORM_METADATA}