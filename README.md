# Migrating Moodle to Container Environment in Azure

This repository contains [Azure Resource Manager](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/overview) templates, customised Moodle image suited for migration requirements based on the [Bitnami Docker Image for Moodle](https://github.com/bitnami/bitnami-docker-moodle) and end to end scripts to automate the migration of the on-premises Moodle App to container environment in Azure such as [Azure Kubernetes Services](https://azure.microsoft.com/en-in/services/kubernetes-service/). A step by step guide to perform the migration using the provided scripts can also be found below.

## Directory Structure

## Infrastructure to deploy in AKS

## Prerequisites
The script is must be executed on the Virtual/Physical Machine hosting a Moodle web server. If there are multiple of them hosting web server behind a load balancer, the script should only be executed on one of the machines (you can choose any one of the machines). It is also important to ensure that there is only one moodle instance running on the webserver.

### 1. Commands required
The following need to be available on the on-prem system before we can perform the migration:
```
tar
python3
mysqldump
locate
bc
```
Steps to install [locate](https://askubuntu.com/questions/215503/how-to-install-the-locate-command/215509#215509) and [bc](https://askubuntu.com/questions/550985/installing-bc-and-any-maths-extension).

### 2. Azure CLI install and login
- Additionally, we need to install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/what-is-azure-cli). The Azure CLI [installation guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt) can be followed or you can simply run the command below:
```
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```
- Login to Azure account which has permission to create resource group, resources in the subscription either interactively using ```az login``` or through the command line with ```az login -u <username> -p <password>```.

- Now, set default subscription with the command below while replacing ```<subscription>``` with the name of your intended default subscription:
```
az account set --subscription <subscription>
```

### 3. Set necessary permissions
Ensure that script executer has the following permissions. They can be set using ```chmod``` [command](https://linuxize.com/post/chmod-command-in-linux/):
 - **read permissions** for *moodledata* folder, *moodle* folder and its contents, *config.php* and *version.php* located in moodle folder. 
 - **execute permissions** for performing database dump on the moodle database.

## Step by step guide to migrate to Azure
Firstly, this repository must be cloned
```
git clone https://github.com/neerajajaja/moodle-to-azure-aks.git
```
Ensure that ```./moodle-migration/migrate-moodle.sh``` and all the scripts in ```./moodle-migration/scripts``` has execute permissions.
```
chmod -R 755 moodle-migration
```
Execute ```./moodle-migration/migrate-moodle.sh``` script file. This will perform the end to end migration.
```
cd moodle-migration
bash migrate-moodle.sh
```
```migrate-moodle.sh``` takes the following self explainable inputs:
- Location of Azure resource group
- Name of Azure resource group

Status of Migration will be updated in the coonsole till the deployment is completed successfully.

The script outputs the *Controller VM IP*, *ssh Username* and the *private and public ssh key files* for the controller vm. This can be used to ssh into the controller vm to perform administrative tasks.

The Loadbalancer IP after the migration is performed can be gotten as below:
- SSH into controller VM using the credentials and IP printed out as output
- Run the commands below to echo the loadbalancer IP:
  ```
  export SERVICE_IP=$(kubectl get svc --namespace default moodle --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}")
  echo "Moodle(TM) URL: http://$SERVICE_IP/"
  ```
- Alternatively, the loadbalancer IP can be found from the Azure portal as well.
  1. Select the AKS resource after navigating to your resource group(this name would have been entered by you as input) in the specified subscription.
  2. Select Service and Ingress on the left
  3. The loadbalancer ip corresponding to moodle can then be found










