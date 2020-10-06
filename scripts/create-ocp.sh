#!/bin/bash

set -e

if [ ! -e helper/parameters.sh ]; then
	echo "ERROR: This script should be invoked from the directory ocs-upi-kvm/scripts"
	exit 1
fi

if [[ -z "$RHID_USERNAME" && -z "$RHID_PASSWORD" && -z "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	echo "ERROR: OR"
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

if [[ -z "$RHID_USERNAME" && -n "$RHID_PASSWORD" ]] || [[ -n "$RHID_USERNAME" && -z "$RHID_PASSWORD" ]]; then
	echo "ERROR: Environment variables RHID_USERNAME and RHID_PASSWORD must both be set"
	exit 1
elif [[ -z "$RHID_ORG" && -n "$RHID_KEY" ]] || [[ -n "$RHID_ORG" && -z "$RHID_KEY" ]]; then
	echo "ERROR: Environment variables RHID_ORG and RHID_KEY must both be set"
	exit 1
fi

export WORKERS=${WORKERS:=3}
export WORKER_DESIRED_MEM=${WORKER_DESIRED_MEM:="65536"}
export WORKER_DESIRED_CPU=${WORKER_DESIRED_CPU:="16"}

source helper/parameters.sh

if [ ! -e $WORKSPACE/pull-secret.txt ]; then
        echo "ERROR: Missing $WORKSPACE/pull-secret.txt.  Download it from https://cloud.redhat.com/openshift/install/pull-secret"
        exit 1
fi

arg1=$1
retry=false
if [ "$1" == "--retry" ]; then
	retry_version=$(sudo virsh list | grep bastion | awk '{print $2}' | sed 's/4-/4./' | sed 's/-/ /g' | awk '{print $2}' | sed 's/ocp//')
	if [ "$retry_version" != "$OCP_VERSION" ]; then
		echo "WARNING: Ignoring --retry argument.  existing version:$retry_version  requested version:$OCP_VERSION"
		retry=false
		unset arg1
	else
		retry=true
	fi
fi

file_present $IMAGES_PATH/$BASTION_IMAGE
if [[ ! -e $WORKSPACE/$BASTION_IMAGE ]] && [[ "$file_rc" != 0 ]]; then
	echo "ERROR: Missing $BASTION_IMAGE.  Get it from https://access.redhat.com/downloads/content/479/ and prepare it per README"
	exit 1
fi

# Remove known_hosts before creating a new cluster to ensure there is
# no SSH conflict arising from previously clusters

if [[ -d ~/.ssh ]] && [[ "$retry" == false ]]; then
	rm -f ~/.ssh/known_hosts
fi

# Setup kvm on the host

if [ ! -e ~/.kvm_setup ]; then
	touch ~/.kvm_setup
	echo "Invoking setup-kvm-host.sh"
	sudo -sE helper/setup-kvm-host.sh
fi

if [ "$retry" == false ]; then
	echo "Invoking virsh-cleanup.sh"
	sudo -sE helper/virsh-cleanup.sh
fi

echo "export PATH=$WORKSPACE/bin/:$PATH" | tee $WORKSPACE/env-ocp.sh
chmod a+x $WORKSPACE/env-ocp.sh

export PATH=$WORKSPACE/bin:$PATH

helper/create-cluster.sh $arg1

scp -o StrictHostKeyChecking=no root@192.168.88.2:/usr/local/bin/oc $WORKSPACE/bin
scp -o StrictHostKeyChecking=no -r root@192.168.88.2:openstack-upi/auth $WORKSPACE

echo "export KUBECONFIG=$WORKSPACE/auth/kubeconfig" | tee -a $WORKSPACE/env-ocp.sh

export KUBECONFIG=$WORKSPACE/auth/kubeconfig

sudo -sE helper/add-data-disks.sh
sudo -sE helper/check-health-cluster.sh

echo ""
echo "To access the cluster:"
echo "source $WORKSPACE/env-ocp.sh"
echo "oc get nodes -o wide"
