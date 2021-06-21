# Moodle container image for Migration

This folder contains the customised Moodle container image suitable to our migration requirements.

This image supports PHP versions 7.2,7.3 and 7.4. Sample command to [build](https://github.com/neerajajaja/moodle-to-azure-aks/blob/master/moodle-arm-templates/scripts/install_moodle.sh#L238) the image:
```
docker build
    --build-arg PHP_VERSION=$phpV       
    --build-arg APACHE_VERSION=$apacheVersion
    --build-arg LIBPHP_VERSION=$phpV
    --build-arg LIBPHP_CS=$libphpCS       # libphp checksum to verify package integrity
    --build-arg PHP_CS=$phpCS         # php checksum to verify package integrity
    --build-arg APACHE_CS=$apacheCS       # apache checksum to verify package integrity
    -t moodle-image     #tag name
    .       # Location of folder containing Dockerfile
```
The container doesn't perform a fresh installation of moodle, instead it picks up the mode code and data copied from on-prem from azure file share which we use as persistent volume.

Further, our Moodle container is deployed to Kubernetes with the help of this [Bitnami Helm chart](https://github.com/bitnami/charts/tree/master/bitnami/moodle).

Sample command to [deploy](https://github.com/neerajajaja/moodle-to-azure-aks/blob/master/moodle-arm-templates/scripts/install_moodle.sh#L256) above helm chart with migration suitable parameters:
```
helm install moodle bitnami/moodle \
    --set image.registry=$ACRname.azurecr.io      # image is pulled from ACR
    --set image.pullSecrets[0]=acr-secret      # Kubernetes secret containing ACR credentials
    --set image.repository=moodle-image      # image repository name in ACR
    --set image.tag=v1      # image tag
    --set moodleSkipInstall=true      # set to true to skip database creation, as we are providing already initialised Azure MySQL DB
    --set mariadb.enabled=false      # bitnami helm chart by default uses MariaDB, disabling so MariaDB chart isn't deployed
    --set extraEnvVars[0].name=MOODLE_DATABASE_TYPE     # setting MOODLE_DATABASE_TYPE in moodle/config.php
    --set extraEnvVars[0].value=mysqli      # setting MOODLE_DATABASE_TYPE to mysqli in moodle/config.php
    --set persistence.enabled=true       # enabling persistence
    --set persistence.existingClaim=azurefile      # provide the name of persistence volume claim created(to afs persistent volume with moodle code and data copied from on-prem)
    --set externalDatabase.host=$SQLServerName      # Created Azure MySQL server name
    --set externalDatabase.port=3306      # Port to connect to external database
    --set externalDatabase.database=$SQLDBName     # MySQL database name
    --set externalDatabase.user=$SQLServerAdmin      # MySQL server admin
    --set externalDatabase.password=$SQLAdminPassword      # MySQL server admin password
    --set containerSecurityContext.runAsUser=0       # By default the helm chart runs the container as a non-root user, to setup cron job, running as root is necessary. Hence, we run container as user 0 or root user here.
 
```

Other parameters of the Bitnami Helm chart can be explored [here](https://github.com/bitnami/charts/tree/master/bitnami/moodle#parameters)



