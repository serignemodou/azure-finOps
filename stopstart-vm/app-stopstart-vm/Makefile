RG_NAME ?= rg-service-faas-appgw-sandbox
WEBAPP_NAME ?= app-service-faas-sandbox
ZIP_NAME=deploy.zip
APP_DIR=.
APP_DIST_DIR=./

.PHONY: help
help:
	@echo '-----------------'
	@grep -E '### deploy azure function app'
	@echo '-----------------'

.PHONY: build
build:
	cd "${APP_DIST_DIR}" && rm -f deploy.zip && zip -r deploy.zip profile.ps1 requirements.psd1 host.json StopStartAppGw/

.PHONE: prod
prod:
	@echo "${RG_NAME}"
	cd "${APP_DIST_DIR}" && unset https_proxy && az functionapp deployment source config-zip --resouce-group ${RG_NAME} --name "${WEBAPP_NAME} --src deploy.zip"