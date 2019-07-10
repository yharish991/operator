#!/usr/bin/env bash

#
# Prerequisite : install tool jq
# This script assumes that KubeDB & Component operators are installed
#
# End to end scenario to be executed on minikube, minishift or k8s cluster
# Example: ./scripts/end-to-end.sh <CLUSTER_IP> <NAMESPACE> <DEPLOYMENT_MODE>
# where CLUSTER_IP represents the external IP address exposed top of the VM
#
CLUSTER_IP=${1:-192.168.99.50}
NS=${2:-test}
MODE=${3:-dev}

SLEEP_TIME=30s
TIME=$(date +"%Y-%m-%d_%H-%M")
REPORT_FILE="result_${TIME}.txt"
EXPECTED_RESPONSE='{"status":"UP"}'
EXPECTED_FRUITS='[{"id":1,"name":"Cherry"},{"id":2,"name":"Apple"},{"id":3,"name":"Banana"}]'
INGRESS_RESOURCES=$(kubectl get ing -n $NS 2>&1)

# Test if we run on plain k8s or openshift
res=$(kubectl api-versions | grep user.openshift.io/v1)
if [ "$res" == "" ]; then
  isOpenShift="false"
else
  isOpenShift="true"
fi

if [ "$MODE" == "build" ]; then
    COMPONENT_FRUIT_BACKEND_NAME="fruit-backend-sb-build"
    COMPONENT_FRUIT_CLIENT_NAME="fruit-client-sb-build"
else
    COMPONENT_FRUIT_BACKEND_NAME="fruit-backend-sb"
    COMPONENT_FRUIT_CLIENT_NAME="fruit-client-sb"
fi

function deleteResources() {
  result=$(kubectl api-resources --verbs=list --namespaced -o name)
  for i in $result[@]
  do
    kubectl delete $i --ignore-not-found=true --all -n $1
  done
}

function listAllK8sResources() {
  result=$(kubectl api-resources --verbs=list --namespaced -o name)
  for i in $result[@]
  do
    kubectl get $i --ignore-not-found=true -n $1
  done
}

function printTitle {
  r=$(typeset i=${#1} c="=" s="" ; while ((i)) ; do ((i=i-1)) ; s="$s$c" ; done ; echo  "$s" ;)
  printf "$r\n$1\n$r\n"
}

function createPostgresqlCapability() {
cat <<EOF | kubectl apply -n ${NS} -f -
apiVersion: "v1"
kind: "List"
items:
- apiVersion: devexp.runtime.redhat.com/v1alpha2
  kind: Capability
  metadata:
    name: postgres-db
  spec:
    category: database
    kind: postgres
    version: "10"
    parameters:
    - name: DB_USER
      value: admin
    - name: DB_PASSWORD
      value: admin
EOF
}
function createFruitBackend() {
cat <<EOF | kubectl apply -n ${NS} -f -
apiVersion: "v1"
kind: "List"
items:
- apiVersion: devexp.runtime.redhat.com/v1alpha2
  kind: Component
  metadata:
    name: fruit-backend-sb
    labels:
      app: fruit-backend-sb
  spec:
    exposeService: true
    deploymentMode: $MODE
    buildConfig:
      url: https://github.com/snowdrop/component-operator-demo.git
      ref: master
      moduleDirName: fruit-backend-sb
    runtime: spring-boot
    version: 2.1.3
    envs:
    - name: SPRING_PROFILES_ACTIVE
      value: postgresql-kubedb
- apiVersion: "devexp.runtime.redhat.com/v1alpha2"
  kind: "Link"
  metadata:
    name: "link-to-postgres-db"
  spec:
    componentName: $COMPONENT_FRUIT_BACKEND_NAME
    kind: "Secret"
    ref: "postgres-db-config"
EOF
}
function createFruitClient() {
cat <<EOF | kubectl apply -n ${NS} -f -
---
apiVersion: "v1"
kind: "List"
items:
- apiVersion: "devexp.runtime.redhat.com/v1alpha2"
  kind: "Component"
  metadata:
    labels:
      app: "fruit-client-sb"
      version: "0.0.1-SNAPSHOT"
    name: "fruit-client-sb"
  spec:
    deploymentMode: $MODE
    buildConfig:
      url: https://github.com/snowdrop/component-operator-demo.git
      ref: master
      moduleDirName: fruit-client-sb
    runtime: "spring-boot"
    version: "2.1.3.RELEASE"
    exposeService: true
- apiVersion: "devexp.runtime.redhat.com/v1alpha2"
  kind: "Link"
  metadata:
    name: "link-to-fruit-backend"
  spec:
    kind: "Env"
    componentName: $COMPONENT_FRUIT_CLIENT_NAME
    envs:
    - name: "ENDPOINT_BACKEND"
      value: "http://fruit-backend-sb:8080/api/fruits"
EOF
}

function createAll() {
  createPostgresqlCapability
  createFruitBackend
  createFruitClient
}

printTitle "Creating the namespace"
kubectl create ns ${NS}

printTitle "Add privileged SCC to the serviceaccount postgres-db and buildbot. Required for the operators Tekton and KubeDB"
if [ "$isOpenShift" == "true" ]; then
  echo "We run on Openshift. So we will apply the SCC rule"
  oc adm policy add-scc-to-user privileged system:serviceaccount:${NS}:postgres-db
  oc adm policy add-scc-to-user privileged system:serviceaccount:${NS}:build-bot
  oc adm policy add-role-to-user edit system:serviceaccount:${NS}:build-bot
else
  echo "We DON'T run on OpenShift. So need to change SCC"
fi

printTitle "Deploy the component for the fruit-backend, link and capability"
createPostgresqlCapability
createFruitBackend
echo "Sleep ${SLEEP_TIME}"
sleep ${SLEEP_TIME}

printTitle "Deploy the component for the fruit-client, link"
createFruitClient
echo "Sleep ${SLEEP_TIME}"
sleep ${SLEEP_TIME}

printTitle "Report status : ${TIME}" > ${REPORT_FILE}

printTitle "1. Status of the resources created using the CRDs : Component, Link or Capability" >> ${REPORT_FILE}
if [ "$INGRESS_RESOURCES" == "No resources found." ]; then
  for i in components links capabilities pods deployments deploymentconfigs services routes pvc postgreses secret/postgres-db-config
  do
    printTitle "$(echo $i | tr a-z A-Z)" >> ${REPORT_FILE}
    kubectl get $i -n ${NS} >> ${REPORT_FILE}
    printf "\n" >> ${REPORT_FILE}
  done
else
  for i in components links capabilities pods deployments services ingresses pvc postgreses secret/postgres-db-config
  do
    printTitle "$(echo $i | tr a-z A-Z)" >> ${REPORT_FILE}
    kubectl get $i -n ${NS} >> ${REPORT_FILE}
    printf "\n" >> ${REPORT_FILE}
  done
fi

printTitle "2. ENV injected to the fruit backend component"
printTitle "2. ENV injected to the fruit backend component" >> ${REPORT_FILE}
until kubectl get pods -n $NS -l app=$COMPONENT_FRUIT_BACKEND_NAME | grep "Running"; do sleep 5; done
kubectl exec -n ${NS} $(kubectl get pod -n ${NS} -lapp=$COMPONENT_FRUIT_BACKEND_NAME | grep "Running" | awk '{print $1}') env | grep DB >> ${REPORT_FILE}
printf "\n" >> ${REPORT_FILE}

printTitle "3. ENV var defined for the fruit client component"
printTitle "3. ENV var defined for the fruit client component" >> ${REPORT_FILE}
until kubectl get pods -n $NS -l app=$COMPONENT_FRUIT_CLIENT_NAME | grep "Running"; do sleep 5; done
for item in $(kubectl get pod -n ${NS} -lapp=$COMPONENT_FRUIT_CLIENT_NAME --output=name); do printf "Envs for %s\n" "$item" | grep --color -E '[^/]+$' && kubectl get "$item" -n ${NS} --output=json | jq -r -S '.spec.containers[0].env[] | " \(.name)=\(.value)"' 2>/dev/null; printf "\n"; done >> ${REPORT_FILE}
printf "\n" >> ${REPORT_FILE}

if [ "$MODE" == "dev" ]; then
  printTitle "Push fruit client and backend"
  ./demo/scripts/k8s_push_start.sh fruit-backend sb ${NS}
  ./demo/scripts/k8s_push_start.sh fruit-client sb ${NS}
fi

printTitle "Wait until Spring Boot actuator health replies UP for both microservices"
for i in $COMPONENT_FRUIT_BACKEND_NAME $COMPONENT_FRUIT_CLIENT_NAME
do
  HTTP_BODY=""
  until [ "$HTTP_BODY" == "$EXPECTED_RESPONSE" ]; do
    HTTP_RESPONSE=$(kubectl exec -n $NS $(kubectl get pod -n $NS -lapp=$i | grep "Running" | awk '{print $1}') -- curl -L -w "HTTPSTATUS:%{http_code}" -s localhost:8080/actuator/health 2>&1)
    HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
    echo "$i: Response is : $HTTP_BODY, expected is : $EXPECTED_RESPONSE"
    sleep 10s
  done
done

printTitle "Curl Fruit service"
printTitle "4. Curl Fruit Endpoint service"  >> ${REPORT_FILE}

if [ "$INGRESS_RESOURCES" == "No resources found." ]; then
    echo "No ingress resources found. We run on OpenShift" >> ${REPORT_FILE}
    FRONTEND_ROUTE_URL=$(kubectl get route/fruit-client-sb -o jsonpath='{.spec.host}' -n ${NS})
    CURL_RESPONSE=$(curl http://$FRONTEND_ROUTE_URL/api/client)
    echo $CURL_RESPONSE >> ${REPORT_FILE}
else
    FRONTEND_ROUTE_URL=fruit-client-sb.$CLUSTER_IP.nip.io
    CURL_RESPONSE=$(curl -H "Host: fruit-client-sb" ${FRONTEND_ROUTE_URL}/api/client)
    echo $CURL_RESPONSE >> ${REPORT_FILE}
fi

if [ "$CURL_RESPONSE" == "$EXPECTED_FRUITS" ]; then
   printTitle "CALLING FRUIT ENDPOINT SUCCEEDED USING MODE : $MODE :-)"
else
   printTitle "FAILED TO CALL FRUIT ENDPOINT USING MODE : $MODE :-("
   exit 1
fi

printTitle "Delete the resources components, links and capabilities"
if [ "$isOpenShift" == "true" ]; then
  kubectl delete components,links,capabilities,imagestreams --all -n ${NS}
else
  kubectl delete components,links,capabilities --all -n ${NS}
fi
