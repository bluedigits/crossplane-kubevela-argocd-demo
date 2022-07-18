# Source: https://gist.github.com/6fb3e7da327df9203d9d4c184fcb5831

##############################################################################
# Combining Argo CD (GitOps), Crossplane (Control Plane), And Kubevela (OAM) #
# https://youtu.be/eEcgn_gU3SM                                               #
##############################################################################

# Referenced videos:
# - Argo CD - Applying GitOps Principles To Manage Production Environment In Kubernetes: https://youtu.be/vpWQeoaiRM4
# - Cloud-Native Apps With Open Application Model (OAM) And KubeVela: https://youtu.be/2CBu6sOTtwk
# - Crossplane - GitOps-based Infrastructure as Code through Kubernetes API: https://youtu.be/n8KjVmuHm7A
# - How to apply GitOps to everything - combining Argo CD and Crossplane: https://youtu.be/yrj4lmScKHQ
# - How To Shift Left Infrastructure Management Using Crossplane Composites: https://youtu.be/AtbS1u2j7po
# - Bitnami Sealed Secrets - How To Store Kubernetes Secrets In Git Repositories: https://youtu.be/xd2QoV6GJlc
# - Terraform vs. Pulumi vs. Crossplane - Infrastructure as Code (IaC) Tools Comparison: https://youtu.be/RaoKcJGchKM
# - Portainer - Container Management Made Easy: https://youtu.be/-mWUbDHTEkQ
# - Ketch - How to Simplify Kubernetes Deployments: https://youtu.be/sMOIiTfGnj0
# - Shipa - A Kubernetes platform from developer's perspective: https://youtu.be/aCwlI3AhNOY
# - Flux CD v2 With GitOps Toolkit - Kubernetes Deployment And Sync Mechanism: https://youtu.be/R6OeIgb7lUI
# - GitHub CLI - How to manage repositories more efficiently: https://youtu.be/BII6ZY2Rnlc

#########
# Setup #
#########

# Create a Kubernetes cluster with Ingress. It can be a local (e.g., KinD, minikube, etc.) or a remote cluster.
# Example tutorial taken from: https://dev.to/francoislp/local-kubernetes-cluster-with-ingress-3cl
# ./k8s/create-cluster-kind.sh

# Install the crossplane system. Taken from: https://crossplane.io/docs/v1.9/getting-started/install-configure.html#install-crossplane
# ./crossplane/install-crossplane.sh

# Install the sealed secrets controller into K8s:
# kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/controller.yaml

# Replace `[...]` with the external IP of the Ingress service
export INGRESS_HOST=localhost

# Replace `[...]` with the GitHub organization or user
export GITHUB_ORG=bluedigits

# Install Crossplane CLI from https://crossplane.io/docs/v1.3/getting-started/install-configure.html#start-with-a-self-hosted-crossplane
# curl -sL https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh | sh

export REPO_URL=https://github.com/$GITHUB_ORG/crossplane-kubevela-argocd-demo

cat production/sealed-secrets.yaml |
    sed -e "s@repoURL: .*@repoURL: $REPO_URL@g" |
    tee production/sealed-secrets.yaml

cat production/crossplane.yaml |
    sed -e "s@repoURL: https://github.com.*@repoURL: $REPO_URL@g" |
    tee production/crossplane.yaml

cat production/team-a-infra.yaml |
    sed -e "s@repoURL: .*@repoURL: $REPO_URL@g" |
    tee production/team-a-infra.yaml

cat orig/team-app-reqs.yaml |
    sed -e "s@repoURL: .*@repoURL: $REPO_URL@g" |
    tee orig/team-app-reqs.yaml

cat orig/team-apps.yaml |
    sed -e "s@repoURL: .*@repoURL: $REPO_URL@g" |
    tee orig/team-apps.yaml

cat apps.yaml |
    sed -e "s@repoURL: .*@repoURL: $REPO_URL@g" |
    tee apps.yaml

# Install bitnami's sealed-secrets controller
#
kubectl apply -f sealed-secrets

#############
# Setup AWS #
#############

# Replace `[...]` with your access key ID`
export AWS_ACCESS_KEY_ID="ASIA4LH22LMXBWTVSGX7"

# Replace `[...]` with your secret access key
export AWS_SECRET_ACCESS_KEY="a2hO+yHYlvDSyKZ2UsGSv9lwnkisx9Fm/khhuYQ2"

echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
" | tee aws-creds.conf

kubectl --namespace crossplane-system \
    create secret generic aws-creds \
    --from-file creds=./aws-creds.conf \
    --output json \
    --dry-run=client |
    kubeseal --format yaml |
    tee crossplane-configs/aws-creds.yaml

#################
# Setup Argo CD #
#################

git add .

git commit -m "Personalization"

git push

helm repo add argo \
    https://argoproj.github.io/argo-helm

helm repo update

helm upgrade --install \
    argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --set server.ingress.hosts="{argo-cd.$INGRESS_HOST.nip.io}" \
    --set server.ingress.enabled=true \
    --set server.extraArgs="{--insecure}" \
    --set controller.args.appResyncPeriod=30 \
    --wait

kubectl apply --filename project.yaml

kubectl apply --filename apps.yaml

PASS=$(kubectl \
    --namespace argocd \
    get secret argocd-initial-admin-secret \
    --output jsonpath="{.data.password}" |
    base64 --decode)
export PASS

argocd login \
    --insecure \
    --username admin \
    --password "$PASS" \
    --grpc-web \
    argo-cd.$INGRESS_HOST.nip.io

argocd account update-password \
    --current-password "$PASS" \
    --new-password admin123

echo http://argo-cd.$INGRESS_HOST.nip.io

# Open it in a browser

# Use `admin` as both the username and password

# Open a second terminal and go to the same directory as in the first

##########
# GitOps #
##########

# Observe the Argo CD UI and wait until the apps are rolled out

##################
# Infrastructure #
##################

cat orig/cluster.yaml

cp orig/cluster.yaml team-a-infra/.

git add .

git commit -m "Team A infra"

git push

# In the second terminal
kubectl get clusters,nodegroup,iamroles,iamrolepolicyattachments,vpcs,securitygroups,subnets,internetgateways,routetables,providerconfigs.helm.crossplane.io,releases

# It might take a while until Argo CD detects the changes and the resources appear.

# Wait until all the resources are ready and synced

chmod +x config-cluster-aws.sh

./config-cluster-aws.sh team-a

################
# Applications #
################

cat orig/my-app.yaml

cp orig/my-app.yaml team-a-apps/.

git add .

git commit -m "Team A apps"

git push

# In the second terminal
export KUBECONFIG=$PWD/kubeconfig.yaml

# In the second terminal
kubectl --namespace production \
    get all,hpa,ingress

##########################
# How did it all happen? #
##########################

# In the second terminal
cat apps.yaml

# In the second terminal
ls -1 production

# In the second terminal
cat production/team-a-infra.yaml

# In the second terminal
ls -1 team-a-infra

# In the second terminal
cat crossplane-compositions/definition.yaml

# In the second terminal
cat crossplane-compositions/cluster-aws.yaml

cat team-a-infra/cluster.yaml

# In the second terminal
cat team-a-app-reqs/kubevela.yaml

cat team-a-apps/my-app.yaml

# Show Argo CD

###########################
# Deleting infrastructure #
###########################

rm team-a-infra/cluster.yaml

git add .

git commit -m "Remove the cluster"

git push

# In the second terminal
unset KUBECONFIG

# In the second terminal
kubectl get clusters,nodegroup,iamroles,iamrolepolicyattachments,vpcs,securitygroups,subnets,internetgateways,routetables,providerconfigs.helm.crossplane.io,releases

# Wait until all the resources are removed

###########
# Destroy #
###########

rm -rf team-a-apps

rm -rf team-a-app-reqs

rm production/team-a-apps.yaml

rm production/team-a-app-reqs.yaml

git add .

git commit -m "Revert"

git push

# Delete the cluster
