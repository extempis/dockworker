#!/bin/bash

#   Copyright 2022 exTempis

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

VERSION=0.0.0
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

trap 'rm -fr $TEMPDIR "$LIST_FILE" $LOGERROR' EXIT

CMD=
DIR_PREFIX="$PWD/dl"
hostname=
OPTION_ALL=
TEMPDIR=
FILENAME=
IMAGENAME=
SOURCE=
DESTINATION=

LOGERROR=$(mktemp)
LIST_FILE=$(mktemp)
touch "$LIST_FILE"

_RESET=$(tput sgr0)
_GREEN=$(tput setaf 2)
_BLUE=$(tput setaf 4)
_RED=$(tput setaf 1)
_YELLOW=$(tput setaf 3)
_WHITE=$(tput setaf 7)
ERASETOEOL="\033[K"

SUCCES=200
CLIENT_ERROR=400
UNAUTHORIZED=401
FORBIDDEN=403
NOTFOUND=404
SERVER_ERROR=500
SERVER_TMOUT=504

CURL="curl -k -n -s "

usage () {
    cat <<HELP_USAGE
    version: $VERSION

    Copyright 2022 exTempis 
    License Apache 2.0

    -------------------------------
    Setup
    -------------------------------
    In order to avoid passing the login/password pair as an argument each time, 
    this tool uses the ~/.netrc file.

    Credential setup :
      $ $(basename $0) login https://nexus3.onap.org/repository/docker.public
    -------------------------------

    -------------------------------
    Usage
    -------------------------------
    # Get tool's version
    $ dockworker.bash version

    # List all container's images in a registry
    $ dockworker.bash list -u registry_url
      $ dockworker.bash list -u https://nexus3.onap.org/repository/docker.public

    # Pull a container's image
    $ dockworker.bash pull -u registry_url -i "root/image:tag"
      $ dockworker.bash pull -u https://nexus3.test.org/repository/container.public -i ubi8:latest
    # You can specify a folder as destination
      $ dockworker.bash pull -u https://nexus3.test.org/repository/container.public -i ubi8:latest -p ./dl

    # Push an oci image archive
    $ dockworker.bash push -u registry_url -s path/file.tar -d image:tag
      $ dockworker.bash push -u https://nexus3.onap.org/repository/docker.public -s ubi8.tar -d ubi8:latest

    # Pull all container's images to a folder
    $ dockworker.bash pull -u registry_url --all -p somefolder
      $ dockworker.bash pull --all -u https://nexus3.onap.org/repository/docker.public -p ./dl

    # Push all container's image from a folder
    $ dockworker.bash push -u registry_url --all -p somefolder
      $ dockworker.bash push --all -u https://nexus3.onap.org/repository/docker.public -p ./dl

    # Tag a container's image
    $ dockworker.bash tag -u registry_url -s image:tag -d new_name:new_tag
      $ dockworker.bash tag -u https://nexus3.onap.org/repository/docker.public -s ubi8/nginx-120:latest -d ubi8/nginx-120:v1.0.0

    Note:
      Behind a proxy, you must set environment variables :
      on linux:   http_proxy/https_proxy
      on windows: HTTP_PROXY/HTTPS_PROXY

HELP_USAGE
}

parse_args() {
  # parsing verb
  case "$1" in
    "login")
      BASE_URL=$(echo ${2%/})
      init_credentials
      ;;
    "list")
      CMD="LIST"
      ;;
    "pull")
      CMD="PULL"
      ;;
    "push")
      CMD="PUSH"
      ;;
    "delete")
      CMD="DELETE"
      ;;
    "tag")
      CMD="TAG"
      ;;
    "version")
      echo "Version : $VERSION"
      exit 0
      ;;
    *) 
      usage
      exit 1
      ;;
  esac
  shift
  
  VALID_ARGS=$(getopt -o af:u:p:i:s:d:h --long all,url:,file:,image:,prefix:,source:,destination:,help -- "$@")
  if [[ $? -ne 0 ]]; then
      exit 1;
  fi
  #[[ $# -eq 0 ]] && usage && exit 0

  eval set -- "$VALID_ARGS"
  while [ : ]; do
    case "$1" in
      -u | --url)
          BASE_URL=$(echo ${2%/})
          hostname=$(echo "$BASE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
          shift 2
          ;;
      -a | --all)
          OPTION_ALL="--all"
          shift
          ;;
      -p | --prefix)
          DIR_PREFIX="$(realpath $2)"
          shift 2
          ;;
      -f | --file)
          FILENAME="$(realpath $2)"
          shift 2
          ;;
      -i | --image)
          IMAGENAME="$2"
          shift 2
          ;;
      -s | --source)
          SOURCE="$2"
          shift 2
          ;;
      -d | --destination)
          DESTINATION="$2"
          shift 2
          ;;
      -h | --help)
          echo "Version : $VERSION"
          usage
          shift
          ;;
      --) shift; 
        break 
        ;;
      *) shift;
          echo "${_RED}Error:${_RESET} Unknow flag: $2"
          exit 1
          ;;
    esac
  done
}

init_credentials() {
  # Verify inputs
  [ -z "$BASE_URL" ] && usage && echo "${_RED}Missing url${_RESET}" && exit 1

  #Get user lgin/password
  read -p 'Username: ' username
  read -sp 'Password: ' password
  echo

  # Try first if the credential is correct
  HTTP_STATUS=$($CURL -o /dev/null -w "%{http_code}" -u $username:"$password" -X 'GET' $BASE_URL -H 'accept: application/json')
  if [ $? -ne 0 ] || [ ${HTTP_STATUS} -ne ${SUCCES} ]
  then
    echo -e "Error: ${_RED}invalid${_RESET} username/password (http_code $HTTP_STATUS)"
    exit 1
  fi
  echo -e "Login ${_GREEN}Succeeded!${_RESET}"

  #Record information to netrc file
  touch ~/.netrc
  chmod 0600 ~/.netrc
  hostname=$(echo "$BASE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
  content=$(cat ~/.netrc | grep -v "machine $hostname login $username ")
  echo "$content" > ~/.netrc
  echo "machine $hostname login $username password $password" >> ~/.netrc
  echo -e "The crendential is stored in ~/.netrc."

  exit 0
}

ping() {
  # Verify inputs
  [ -z "$BASE_URL" ] && usage && echo "${_RED}Missing base url${_RESET}" && exit 1

  HTTP_STATUS=$($CURL -o /dev/null -w "%{http_code}" -X 'GET' $BASE_URL/v2/_catalog -H 'accept: application/json')
  if [ $? -ne 0 ] || [ ${HTTP_STATUS} -ne ${SUCCES} ]
  then
    echo -e "${_RED}Error:${_RESET} Can not access to the container registry."
    echo -e "${_RED}Error:${_RESET} Verify your credential or your url, and try :"
    echo -e "$(basename $0) login $BASE_URL"
    exit 1
  fi
  echo -e "Ping container registry : [${_GREEN}OK${_RESET}]"
}


list_images() {
  TEMPDIR=$(mktemp -d)

  :> "$LIST_FILE"
  #Retrieve a sorted, json list of repositories available in the registry.
  $CURL "${BASE_URL}/v2/_catalog" -H 'accept: application/json' -o $TEMPDIR/registry.json

  #Fetch the tags under the repository
  for r in $(jq -r .repositories[] $TEMPDIR/registry.json)
  do
    $CURL "${BASE_URL}/v2/$r/tags/list" -H 'accept: application/json' -o $TEMPDIR/$(echo "$r".json | tr "/" "_")
  done

  for file in $(find $TEMPDIR -maxdepth 1 -type f  -name "*.json" | grep -v registry.json)
  do
    image_tags=$(jq -r .tags[] "$file")
    image_name=$(jq -r .name "$file")
    for image_tag in $image_tags 
    do 
      echo -e "$image_name $image_tag" >> "$LIST_FILE"
    done
  done
  rm -fr "$TEMPDIR"
}

dl_manifest() {
  TEMP=$(mktemp)
  BLOBSHA=$($CURL -I "${BASE_URL}/v2/$image_name/manifests/$image_tag" \
            -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
            | grep -i docker-content-digest \
            | sed -E  s/'^.*sha256:([a-z0-9]{64}).*'/'\1'/g )
  $CURL "${BASE_URL}/v2/$image_name/manifests/$image_tag" \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        -o "$TEMP"
  echo "$TEMP" "$BLOBSHA"
}

pull_image() {
  #manifest : /v2/<name>/manifests/<reference>
  #Pulling a Layer: /v2/<name>/blobs/<digest>
  if [ -z "$image_name" ] || [ -z "$image_tag" ]; then
    echo "${_RED}Error:${_RESET} you must specify a image name and a tag."
    exit 1
  fi
  echo "Trying to pull  ${hostname}/$image_name:$image_tag..."
  TEMPDIR=$(mktemp -d)

  mkdir -p $TEMPDIR/blobs/sha256 $DIR_PREFIX

  manifestFile="manifest.json"

  # Download Manifest
  echo -n "Copying manifest "
  var=( $(dl_manifest) )
  BLOBSHA=${var[1]}
  mv "${var[0]}" $TEMPDIR/$manifestFile
  SHA256=$(sha256sum $TEMPDIR/$manifestFile | cut -d' ' -f1)
  short=$(echo "${SHA256/*:/}" | cut -c -12)
  [ "$SHA256" != "${BLOBSHA}" ] && echo "Error: sha256sum for manifest expected $BLOBSHA receive $SHA256" && return
  echo "$short done"

  # Download layers
  BLOBSHAS=$(cat $TEMPDIR/$manifestFile | jq -r .layers[].digest)
  for BLOBSHA in $BLOBSHAS
  do
    short=$(echo "${BLOBSHA/*:/}" | cut -c -12)
    echo -n "Copying blob $short"
    $CURL -L "${BASE_URL}/v2/$image_name/blobs/${BLOBSHA}" -o "$TEMPDIR/blobs/sha256/${BLOBSHA/*:/}"
    # Verify
    SHA256=$(sha256sum "$TEMPDIR/blobs/sha256/${BLOBSHA/*:/}" | cut -d' ' -f1)
    [ "$SHA256" != "${BLOBSHA/*:/}" ] && echo "Error: sha256sum for layer expected ${BLOBSHA/*:/} receive $SHA256"
    [ "$SHA256" == "${BLOBSHA/*:/}" ] && echo " done"
  done

  # Download Config
  BLOBSHA=$(cat $TEMPDIR/$manifestFile | jq -r .config.digest)
  echo -n "Copying config $(echo "${BLOBSHA/*:/}" | cut -c -12)"
  $CURL -L "${BASE_URL}/v2/$image_name/blobs/${BLOBSHA}" -o $TEMPDIR/blobs/sha256/"${BLOBSHA/*:/}"
  # Verify
  SHA256=$(sha256sum $TEMPDIR/blobs/sha256/"${BLOBSHA/*:/}" | cut -d' ' -f1)
  [ "$SHA256" != "${BLOBSHA/*:/}" ] && echo "Error: sha256sum for manifest expected $BLOBSHA receive $SHA256"
  [ "$SHA256" == "${BLOBSHA/*:/}" ] && echo " done"

  # translate manifest to oci compliant
  sed -i -e 's/vnd.docker.image.rootfs.diff.tar.gzip/vnd.oci.image.layer.v1.tar+gzip/g' \
         -e 's/vnd.docker.container.image.v1+json/vnd.oci.image.config.v1+json/g' $TEMPDIR/$manifestFile
  SHA256=$(sha256sum $TEMPDIR/$manifestFile | cut -d' ' -f1)
  cat $TEMPDIR/$manifestFile | jq 'del(.mediaType)' | jq -c . > $TEMPDIR/blobs/sha256/"$SHA256"
  cc=$(cat "$TEMPDIR/blobs/sha256/$SHA256")
  SIZE=$( echo -n "$cc" | wc -c)
  rm -f $TEMPDIR/$manifestFile

  # Add metadata file for oci-archive
  echo -n '{"imageLayoutVersion": "1.0.0"}' > $TEMPDIR/oci-layout
  echo -n "{\"schemaVersion\":2,\"manifests\":[{\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\",\"digest\":\"sha256:${SHA256}\",\"size\":${SIZE},\"annotations\":{\"org.opencontainers.image.ref.name\":\"${hostname}/${image_name}:${image_tag}\"}}]}" > $TEMPDIR/index.json

  # Archive/ bundle image to tar file
  tar_name=$(echo "$image_name""@""$image_tag.tar" | tr "/" "+")
  tar -cf $DIR_PREFIX/"$tar_name" -C $TEMPDIR/ .

  # clean up
  rm -fr $TEMPDIR/
}

pull_all() {
  (list_images)
  [ -s "$LIST_FILE" ] || (echo "Nothing to pull" && return)

  MAX=$(cat "$LIST_FILE" | wc -l)
  iter=0
  while IFS=" " read -r image_name image_tag || [[ -n "$image_name" ]]; do
    echo ">>>$_BLUE $image_name  $image_tag $_RESET"
    (pull_image)
    iter=$(( iter + 1 ))
    echo "Done $iter/$MAX"
    echo
  done < "$LIST_FILE"
}

push_blob() {
  KIND=$1
  location_ini=
  short=$(echo "${layer/*:/}" | cut -c -12)
  layersize=$(stat -c%s "${TEMPDIR}/blobs/sha256/${layer/*:/}")

  # Existing Layers : HEAD /v2/<name>/blobs/<digest> 200 if it exists
  returncode=$($CURL -w "%{http_code}" -IL  \
              -o /dev/null \
              $BASE_URL/v2/"$image_name"/blobs/"$layer" 2> /dev/null)
  [ "$returncode" -eq $SUCCES ] && echo "Copying $KIND ${short} skipped: $_BLUE already exists $_RESET" && return

  TEMP=$(mktemp)

  # Starting An Upload : POST /v2/<name>/blobs/uploads/
  returncode=$($CURL -w "%{http_code}" -v -X POST $BASE_URL/v2/cro/tt/blobs/uploads/ 2> $TEMP)
  location_ini=$(cat $TEMP| grep -i "location:" | cut -d: -f2- | tr -d ' ' | tr -d '\r')
  if [[ "$location_ini" == /v2/* ]]; then
    location=$BASE_URL$location_ini
  else
    location=$location_ini
  fi

  # Upload the blob
  if [ "$returncode" -eq 202 ]
  then
    echo -n "Copying $KIND ${short} "
    returncode=$($CURL -w "%{http_code}" -s -v -H "Content-Length: $layersize"  -H "Connection: close" -H 'Content-Type: application/octet-stream' -X PATCH "$location" --data-binary @"${TEMPDIR}/blobs/sha256/${layer/*:/}" 2> $TEMP)
    [ "$returncode" -ne 202 ] && echo "$_RED error $_RESET" && return
    location=$(cat $TEMP| grep -i "location:" | cut -d: -f2- | tr -d ' ' | tr -d '\r')
    :>$TEMP
    if [[ "$location_ini" == /v2/* ]]; then
      location=$BASE_URL$location_ini
      returncode=$($CURL    -v -w "%{http_code}" -X PUT -H "Content-Length: 0" -H "Connection: close" "$location?digest=$layer" 2> $TEMP)
    else
      returncode=$($CURL -s -v -w "%{http_code}" -X PUT -H "Connection: close" -H 'Content-Type: application/octet-stream' -H "Content-Length: 0" "$location&digest=$layer" 2> $TEMP)
    fi
    [ "$returncode" -eq 201 ] && echo "$_GREEN done $_RESET"
    [ "$returncode" -ne 201 ] && echo "$_RED error $_RESET"
  else
    echo "Error: Receive $returncode when starting blob upload"
  fi
  rm -f $TEMP
}

push_image() {
  TEMPDIR=$(mktemp -d)
  mkdir -p ${TEMPDIR}

  tar -xf "$tarfile" -C ${TEMPDIR}
  cc=$(echo "$tarfile" | tr "+" "/")

  anno=$(jq -c .manifests[].annotations ${TEMPDIR}/index.json)
  image_name=$(echo $anno | awk -F ':' '{print $2}' | tr -d '"')
  image_tag=$( echo $anno | awk -F ':' '{print $3}' | tr -d '"}')

  if [ ! -z "$DESTINATION" ]; then
    arrIN=(${DESTINATION//:/ })
    image_name=${arrIN[0]}
    image_tag=${arrIN[1]}
  else
    if [ -z "$image_name" ] 
    then
      image_name=$(echo "$cc" | sed -nE 's/(.*)@.*.tar/\1/p')
      image_tag=$(echo "$cc" | sed -nE 's/.*@(.*).tar/\1/p')

      if [ -z "$image_name" ]
      then
        echo "Error: can not determine destnation image name/tag"
      fi
    else
      # replace hostname
      image_name=${image_name#*/}
    fi
  fi

  echo "Trying to push $file $image_name:$image_tag"
  sha_manifest=$(jq -r .manifests[].digest ${TEMPDIR}/index.json)

  layers=$(jq -r .layers[].digest ${TEMPDIR}/blobs/sha256/"${sha_manifest/*:/}")
  for layer in $layers
  do
    push_blob "blob"
  done

  # Config layer
  file="${TEMPDIR}/blobs/sha256/${sha_manifest/*:/}"
  layer=$(jq -r .config.digest "$file")
  short=$(echo "${layer/*:/}" | cut -c -12)
  push_blob "config"

  # Manifest
  cc=$(cat "$file")
  size=$( echo -n "$cc" | wc -c)
  returncode=$($CURL -w "%{http_code}" -X PUT -H "Content-Type: application/vnd.oci.image.manifest.v1+json" \
                -H "Content-Length: $size" \
                -d "$cc" $BASE_URL/v2/"$image_name"/manifests/"$image_tag" -o ${TEMPDIR}/output)
  [ "$returncode" != "201" ] && msg=$(jq -r .errors[].detail ${TEMPDIR}/output) && echo "Error: while uploading manifest : $msg"
  [ "$returncode" == "201" ] && echo "Writing manifest to image destination" && echo "${sha_manifest/*:/}"

  rm -fr ${TEMPDIR}
  echo ""
}

push_all() {
  for tarfile in $(find ${DIR_PREFIX}/*.tar -maxdepth 1 -type f)
  do
    (push_image)
  done
}

delete_image() {
  #DELETE /v2/<name>/blobs/<digest>
  var=( $(dl_manifest) )
  BLOBSHA=${var[1]}
  rm -f "${var[0]}"
  echo -n "Deleting image $image_name $image_tag sha256:$(echo "${BLOBSHA/*:/}" | cut -c -12)"
  returncode=$($CURL -w "%{http_code}" \
            -o /dev/null -X DELETE \
            "${BASE_URL}/v2/$image_name/manifests/${BLOBSHA/*:/}")
  [ "$returncode" -eq 202  ] && echo " done"
  [ "$returncode" -ne 202  ] && echo " Failed"
}

delete_all() {
  (list_images)
  [ -s "$LIST_FILE" ] || (echo "Nothing to delete" && return)

  MAX=$(cat "$LIST_FILE" | wc -l)
  iter=0
  while IFS=" " read -r image_name image_tag || [[ -n "$image_name" ]]; do
    (delete_image)
    iter=$(( iter + 1 ))
    echo "Done $iter/$MAX"
  done < "$LIST_FILE"
}

tag_image() {
  #PUT /v2/<name>/manifests/<reference>
  image_tag=${1/*:/}
  image_name=${1%:*}
  target_tag=${2/*:/}
  target_name=${2%:*}
  echo -n "Tagging image $image_name $image_tag to $target_name $target_tag"
  TEMP=$(mktemp)

  var=( $(dl_manifest) )
  BLOBSHA=${var[1]}
  file="${var[0]}"
  # Manifest
  cc=$(cat "$file")
  size=$( echo -n "$cc" | wc -c)
  returncode=$($CURL -w "%{http_code}" -X PUT -H "Content-Type: application/vnd.oci.image.manifest.v1+json" \
                -H "Content-Length: $size" \
                -d "$(cat "$file")" ${BASE_URL}/v2/"$target_name"/manifests/"$target_tag" -o $TEMP)
  [ "$returncode" != "201" ] && msg=$(jq -r .errors[].detail $TEMP) && echo " Error: while tagging : $msg"
  [ "$returncode" == "201" ] && echo " done"
  rm -f "${var[0]}" $TEMP
}

parse_args "$@"
case "$CMD" in
  "LIST")
    ping
    echo -n "List images and tags from registry ..."
    list_images
    echo  -e " done.\n"

    cat "$LIST_FILE"
    ;;
  "PULL")
    ping
    if [ "$OPTION_ALL" == "--all" ]; then
      pull_all
    else
      arrIN=(${IMAGENAME//:/ })
      image_name=${arrIN[0]}
      image_tag=${arrIN[1]}
      pull_image
    fi
    ;;
  "PUSH")
    ping
    if [ "$OPTION_ALL" == "--all" ]; then
      push_all
    else
      tarfile=$SOURCE
      push_image
    fi
    ;;
  "TAG")
    ping
    tag_image $SOURCE $DESTINATION
    ;;
  *) 
    exit 1
    ;;
esac
exit 0