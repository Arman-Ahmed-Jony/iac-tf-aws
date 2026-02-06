#!/bin/bash

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y docker.io
