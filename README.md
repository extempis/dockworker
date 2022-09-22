# dockworker

![Issues](https://img.shields.io/github/issues-raw/extempis/dockworker)
![Pull requests](https://img.shields.io/github/issues-pr-raw/extempis/dockworker)
![Total downloads](https://img.shields.io/github/downloads/extempis/dockworker/total.svg)
![GitHub forks](https://img.shields.io/github/forks/extempis/dockworker?label=fork&style=plastic)
![GitHub watchers](https://img.shields.io/github/watchers/extempis/dockworker?style=plastic)
![GitHub stars](https://img.shields.io/github/stars/extempis/dockworker?style=plastic)
![License](https://img.shields.io/github/license/extempis/dockworker)
![Repository Size](https://img.shields.io/github/repo-size/extempis/dockworker)
![Contributors](https://img.shields.io/github/contributors/extempis/dockworker)
![Commit activity](https://img.shields.io/github/commit-activity/m/extempis/dockworker)
![Last commit](https://img.shields.io/github/last-commit/extempis/dockworker)
![Release date](https://img.shields.io/github/release-date/extempis/dockworker)
![Latest Production Release Version](https://img.shields.io/github/release/extempis/dockworker)

Backup and restore oci images from an container image registry.

This tool can download all images from an image registry server
and upload them to another server or the same server in case of corruption or disaster.

This tool has weak dependency : just curl, sha256sum and jq.
It simply uses the API from the image registry.

So it is easy to deploy it on a machine that cannot be updated with the usual packages 
like skopeo, or podman.

Tested with Nexus3 repository (OSS), Openshift, Docker Registry 2.0.

## Installation

### linux 

#### With a rpm package

```bash
$ rpm -ivh dockworker-<version>-1.rpm
```
#### With a deb package

```bash
$ dpkg -i dockworker-<version>.deb
```

#### On other OS 

Install using the tarball file.

```bash
$ tar -C /usr/local/bin/ --strip-components=1 -xvf dockworker-<version>.tar.gz 
```

### Windows 

#### Prerequis

- bash
- curl
- sha256sum/sha1sum
- jq 
  
Install gitbash or cygwin 

To install jq on gitbash

```bash
curl -L -o /usr/bin/jq.exe https://github.com/stedolan/jq/releases/latest/download/jq-win64.exe
```

To install dockworker

```bash
$ tar -C /usr/local/bin/ --strip-components=1 -xvf dockworker-<version>.tar.gz 
```

## Usage

### Check the help menu

```bash
user@oo:~/backup_dir$ dockworker -h

-------------------------------
Setup
-------------------------------
In order to avoid passing the login/password pair as an argument each time,
this tool uses the ~/.netrc file.

Credential setup :
  $ dockworker.bash login https://registry_url.domain
-------------------------------

-------------------------------
Usage
-------------------------------
# Get tool's version
$ dockworker.bash version

# List all container's images in a registry
$ dockworker.bash list -u registry_url
  $ dockworker.bash list -u https://registry.domain/repo/

# Pull a container's image
$ dockworker.bash pull -u registry_url -i "root/image:tag"
  $ dockworker.bash pull -u https://registry.domain/repo

# Push an oci image archive
$ dockworker.bash push -u registry_url -s path/file.tar -d image:tag
  $ dockworker.bash push -u https://registry.domain/repo -s ubi8.tar -d ubi8:latest

# Pull all container's images to a folder
$ dockworker.bash pull -u registry_url --all -p somefolder
  $ dockworker.bash pull --all -u https://registry.domain/repo -p ./dl

# Push all container's image from a folder
$ dockworker.bash push -u registry_url --all -p somefolder
  $ dockworker.bash push --all -u https://registry.domain/repo -p ./dl

# Tag a container's image
$ dockworker.bash tag -u registry_url -s image:tag -d new_name:new_tag
  $ dockworker.bash tag -u https://registry.domain/repo -s ubi8/nginx-120:latest -d ubi8/nginx-120:v1.0.0

```
### To Work behind a proxy

A way to pass the proxy address is to set environment variables :

On Linux

```bash
export http_proxy="[protocol://][host][:port]"
export https_proxy="[protocol://][host][:port]"
```

On windows 

```bash
export HTTP_PROXY="[protocol://][host][:port]"
export HTTPS_PROXY="[protocol://][host][:port]"
```

To disable global proxy settings, unset these two environment variables.

```bash
unset http_proxy
unset https_proxy
```

## Roadmap 

- Add retry when blob upload failed : timeout
- manage TLS certificate
- delete all image ?
- Error management
- progress bar : list image

## License

[![License](https://img.shields.io/badge/License-Apache_2.0-yellowgreen.svg)](https://opensource.org/licenses/Apache-2.0)

Copyright 2022 exTempis