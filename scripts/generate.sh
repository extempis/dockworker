#!/bin/bash
set -x

SCRIPTDIR=$(dirname -- "$( readlink -f -- "$0"; )")
[ -z "$DESTDIR" ] && DESTDIR=$SCRIPTDIR/../artifacts

RPM_RELEASE=1
TAG_EXACT=$(git describe --exact-match --abbrev=0 --tags)
TAG_NEAR=$(git describe --abbrev=0 --tags)
COMMIT_TAG=$(git rev-parse --short HEAD)

if [ -z $TAG_EXACT ]; then 
  VERSION=$TAG_NEAR
  COMMIT_TAG=${COMMIT_TAG}
else
  VERSION=$TAG_EXACT
  COMMIT_TAG=
fi

[ -z "$COMMIT_TAG" ]  && sed -i -e "s|^VERSION=.*|VERSION=$VERSION|g" $SCRIPTDIR/../src/dockworker.bash
[ ! -z "$COMMIT_TAG" ]  && sed -i -e "s|^VERSION=.*|VERSION=$VERSION-$COMMIT_TAG|g" $SCRIPTDIR/../src/dockworker.bash

cat $SCRIPTDIR/../src/dockworker.bash | grep VERSION

DESTDIR=$(readlink -f "${DESTDIR}")
TARDIR="${DESTDIR}/dockworker-${VERSION}"

mkdir -p ${TARDIR}

# generate binary
cat ${SCRIPTDIR}/script.sh > ${TARDIR}/dockworker
base64 ${SCRIPTDIR}/../src/dockworker.bash >> ${TARDIR}/dockworker
chmod +x ${TARDIR}/dockworker

# generate footprint
cd ${TARDIR}
sha256sum dockworker > dockworker.sha256.txt

# generate archive
cd ${DESTDIR}
tar czvf dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz dockworker-${VERSION}

# generate rpm
mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz ~/rpmbuild/SOURCES

if [ -z $TAG_EXACT ]; then 
  rpmbuild --target noarch  --define "VERSION ${VERSION}" --define "RPM_RELEASE ${RPM_RELEASE}" --define "COMMIT_TAG ${COMMIT_TAG}" -bb ${SCRIPTDIR}/../packages/dockworker.spec
else
  rpmbuild --target noarch  --define "VERSION ${VERSION}" --define "RPM_RELEASE ${RPM_RELEASE}"  -bb ${SCRIPTDIR}/../packages/dockworker.spec
fi
cp -v ~/rpmbuild/RPMS/noarch/*.rpm ${DESTDIR}

# generate deb
mkdir -p $DESTDIR/deb/dockworker/usr/local/bin $DESTDIR/deb/dockworker/DEBIAN
cp -v ${TARDIR}/* $DESTDIR/deb/dockworker/usr/local/bin
cat <<EOF > $DESTDIR/deb/dockworker/DEBIAN/control
Package: dockworker
Version: ${VERSION}-${RPM_RELEASE}${COMMIT_TAG}
Maintainer: extempis
Architecture: all
Description: Tools for backup and restore nexus 3 repository
EOF

cd $DESTDIR/deb/
dpkg-deb --build dockworker
mv dockworker.deb $DESTDIR/dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb

cd ${DESTDIR}

# generate footprints
sha256sum dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz > dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz.sha256.txt
sha256sum dockworker-${VERSION}-*.rpm > dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.noarch.rpm.sha256.txt
sha256sum dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb > dockworker-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb.sha256.txt

# Verify sha
sha256sum -c dockworker-*.txt