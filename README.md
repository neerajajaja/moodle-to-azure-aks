# Migrating Moodle to Container Environment in Azure

This repository contains [Azure Resource Manager](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/overview) templates, customised Moodle image suited for migration requirements based on the [Bitnami Docker Image for Moodle](https://github.com/bitnami/bitnami-docker-moodle) and end to end scripts to automate the migration of the on-premises Moodle App to container environment in Azure such as [Azure Kubernetes Services](https://azure.microsoft.com/en-in/services/kubernetes-service/).

## Directory Structure

## Infrastructure to deploy in AKS

## Prerequisites

### 1. Commands required
The following need to be available on the on-prem system before we can perform the migration:
```
tar
python3
mysqldump
locate
bc
```
Steps to install [locate](https://askubuntu.com/questions/215503/how-to-install-the-locate-command/215509#215509) and [bc](https://askubuntu.com/questions/550985/installing-bc-and-any-maths-extension)

### 2. Azure CLI install and login
Additionally, we need to install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/what-is-azure-cli). The Azure CLI [installation guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt) can be followed or you can simply run the command below:
```
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```
Login to Azure account which has permission to create resource group, resources in the subscription either interactively using ```az login``` or through the command line with ```az login -u <username> -p <password>```.

Set default subscription with the command below while replacing ```<subscription>``` with the name of your intended default subscription
```
az account set --subscription <subscription>
```




