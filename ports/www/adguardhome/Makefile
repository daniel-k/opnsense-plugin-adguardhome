PORTNAME=	adguardhome
DISTVERSIONPREFIX=	v
DISTVERSION=	0.107.77
PORTREVISION=		2
CATEGORIES=	www
MASTER_SITES=	https://github.com/AdguardTeam/AdGuardHome/releases/download/${DISTVERSIONPREFIX}${DISTVERSION}/
DISTNAME=	AdGuardHome_freebsd_amd64
DIST_SUBDIR=	${PORTNAME}-${DISTVERSION}

MAINTAINER=	github@daniel-krebs.net
COMMENT=	Network-wide ads & trackers blocking DNS server
WWW=		https://adguard.com/en/adguard-home/overview.html \
		https://github.com/AdguardTeam/AdGuardHome

LICENSE=	GPLv3
LICENSE_FILE=	${WRKSRC}/LICENSE.txt

ONLY_FOR_ARCHS=	amd64
ONLY_FOR_ARCHS_REASON=	This repository ships the prebuilt AdGuard Home binary for amd64 only

# Needed at runtime for TLS upstreams (DNS-over-TLS/HTTPS) and update checks.
RUN_DEPENDS=	ca_root_nss>=0:security/ca_root_nss

# This port installs the upstream prebuilt FreeBSD/amd64 binary, so there is
# nothing to compile. Building AdGuard Home from source additionally requires a
# Go toolchain and a Node.js frontend build; the official release tarball avoids
# both while producing the exact binary AdGuard ships.
NO_BUILD=	yes

USE_RC_SUBR=	${PORTNAME}

# Dedicated, unprivileged service account (created by pkg-install via pw(8);
# nologin shell, no writable home outside the work dir). AdGuard Home never runs
# as root and never binds a privileged port in the recommended setup. The rc
# script derives the group from the user's primary group, so only USER is
# substituted. The os-adguardhome plugin can override the run-as user at runtime
# via /etc/rc.conf.d/adguardhome, but defaults to this same account.
ADGUARDHOME_USER=	adguardhome
SUB_LIST=	USER=${ADGUARDHOME_USER}

# The release tarball extracts to ./AdGuardHome/ (binary + docs + LICENSE).
WRKSRC=		${WRKDIR}/AdGuardHome

PLIST_FILES=	bin/${PORTNAME}

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/AdGuardHome ${STAGEDIR}${PREFIX}/bin/${PORTNAME}

.include <bsd.port.mk>
