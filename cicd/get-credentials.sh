#!/bin/bash
# Execute the idpbuilder command and store the output in a variable
output=$(idpbuilder get secrets)
# Extract the ArgoCD password using grep and awk
argocd_password=$(echo "$output" | grep -A 3 "argocd-initial-admin-secret" | grep "password" | awk '{print $3}')
gitea_password=$(echo "$output" | grep -A 3 "gitea-credential" | grep "password" | awk '{print $3}')
keycloak_password=$(echo "$output" | grep -A 9 "keycloak-config" | grep "USER_PASSWORD" | awk '{print $3}')
# Create the credentials.txt file with the required ArgoCD details
cat <<EOF > ~/environment/credentials.txt
ArgoCD
        URL : https://${IDE_DOMAIN}/argocd
        Username: admin
        Password: ${argocd_password}
ArgoWorkflows
        URL: https://d3jzhjgbbfbtfo.cloudfront.net/argo-workflows
        Username: user1
        Password: ${keycloak_password}
BackStage
        URL: https://${IDE_DOMAIN}/
        Username: user1
        Password: ${keycloak_password}
Gitea
        URL: https://${IDE_DOMAIN}/gitea
        Username: giteaAdmin
        Password: ${gitea_password}
EOF

echo "credentials.txt file created with ArgoCD details."