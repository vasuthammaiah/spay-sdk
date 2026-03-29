## 1.0.5

* Fix received SKR activity not showing: merge v0 lookup-table addresses into parser, guard accountIndex overflow, fix skrActivity flag for new ATAs.
* Fix activity service: add _isRefreshing guard to prevent concurrent loads, mounted checks, and silent error handling when cached data exists.
* Add 8-second background refresh timer to ActivityService.

## 1.0.4

* Align version with all other SeekerPay packages.

## 1.0.3

* Add `showFungible` parameter to `getAssetsByOwner` to support fungible Token-2022 asset lookups.

## 1.0.2

* Add dartdoc comments to all public APIs.
* Add pub.dev topics for discoverability.

## 1.0.1

* Add example pubspec.yaml referencing published package versions.

## 1.0.0

* Initial open-source release under MIT License.