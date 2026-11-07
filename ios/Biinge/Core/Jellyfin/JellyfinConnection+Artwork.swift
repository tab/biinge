import Foundation
import JellyfinAPI

extension JellyfinConnection {
    /// Landscape art: the item's Thumb, its Backdrop, the parent's Thumb, then the parent's Backdrop
    func landscapeURL(_ item: BaseItemDto, maxWidth: Int) -> URL? {
        if let id = item.id, let tag = item.imageTags?[ImageType.thumb.rawValue] {
            return imageURL(itemID: id, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        if let id = item.id, let tag = item.backdropImageTags?.first {
            return imageURL(itemID: id, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        if let id = item.parentThumbItemID, let tag = item.parentThumbImageTag {
            return imageURL(itemID: id, type: .thumb, tag: tag, maxWidth: maxWidth)
        }
        if let id = item.parentBackdropItemID, let tag = item.parentBackdropImageTags?.first {
            return imageURL(itemID: id, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        return nil
    }

    /// Poster art: an episode's series Primary, then the item's own Primary
    func posterURL(_ item: BaseItemDto, maxWidth: Int) -> URL? {
        // an episode's own Primary is a landscape still, so its series poster comes first
        if item.type == .episode, let id = item.seriesID {
            return imageURL(itemID: id, type: .primary, tag: item.seriesPrimaryImageTag, maxWidth: maxWidth)
        }
        if let id = item.id, let tag = item.imageTags?[ImageType.primary.rawValue] {
            return imageURL(itemID: id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        return nil
    }
}
