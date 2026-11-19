.PHONY: bump build build-release run build-wear build-wear-release

# Local, gitignored dart defines (e.g. APP_CHECK_DEBUG_TOKEN for debug builds)
DART_DEFINES := $(if $(wildcard dart_defines.json),--dart-define-from-file=dart_defines.json)

bump:
	@cur=$$(grep 'version:' pubspec.yaml | cut -d '+' -f2); \
	new=$$(($$cur + 1)); \
	sed -i "s/\+$$cur/\+$$new/" pubspec.yaml; \
	echo "Build $$cur -> $$new"

build: bump
	flutter build apk $(DART_DEFINES)

build-release: bump
	flutter build appbundle --release $(DART_DEFINES)

run: bump
	flutter run $(DART_DEFINES)

# Wear OS companion (android/wear). Same applicationId and signing key as the phone app.
build-wear:
	cd android && ./gradlew :wear:assembleDebug

build-wear-release:
	cd android && ./gradlew :wear:bundleRelease
