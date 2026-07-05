.PHONY: help build clean release-show release-tag bump-adguardhome-revision bump-plugin-revision

help:
	@echo "Targets:"
	@echo "  build  - build adguardhome + os-adguardhome packages (FreeBSD only)"
	@echo "  clean  - remove generated build artifacts"
	@echo "  release-show              - show current package versions and computed release tag"
	@echo "  release-tag               - print computed release tag only"
	@echo "  bump-adguardhome-revision - increment adguardhome PORTREVISION"
	@echo "  bump-plugin-revision      - increment os-adguardhome PLUGIN_REVISION"

build:
	@./scripts/build-packages.sh

clean:
	rm -rf artifacts dns/adguardhome/work ports/www/adguardhome/work

release-show:
	@./scripts/release.sh show

release-tag:
	@./scripts/release.sh tag

bump-adguardhome-revision:
	@./scripts/release.sh bump-adguardhome-revision

bump-plugin-revision:
	@./scripts/release.sh bump-plugin-revision
