import Foundation
import UIKit
import Photos

/// Kümmert sich darum, Bilder zusätzlich im iPhone-Fotoalbum "HA Messung" abzulegen.
enum PhotoLibraryService {
    private static let albumName = "HA Messung"

    static func saveToAlbum(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }

            PHPhotoLibrary.shared().performChanges({
                // Bild-Asset anlegen
                let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                guard let assetPlaceholder = creationRequest.placeholderForCreatedAsset else { return }

                let assets = NSArray(object: assetPlaceholder)

                if let existing = fetchAlbum() {
                    // Vorhandenes Album: Asset hinzufügen
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(for: existing) {
                        albumChangeRequest.addAssets(assets)
                    }
                } else {
                    // Neues Album anlegen und Asset direkt hinzufügen (ohne Fetch)
                    let albumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    albumRequest.addAssets(assets)
                }
            }, completionHandler: nil)
        }
    }

    private static func fetchAlbum() -> PHAssetCollection? {
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var found: PHAssetCollection?
        fetch.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == albumName {
                found = collection
                stop.pointee = true
            }
        }
        return found
    }
}

