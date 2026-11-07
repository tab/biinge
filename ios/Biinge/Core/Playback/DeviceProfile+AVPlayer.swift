import JellyfinAPI

extension DeviceProfile {
    /// What AVPlayer plays: MP4 and MOV directly, the rest as fMP4 HLS with the video copied, and text subtitles as files (after Swiftfin's AVPlayer profile)
    static let avPlayer = DeviceProfile(
        // shortcut: no HDR or Dolby Vision range conditions, add them when the library holds HDR media
        codecProfiles: [
            // AVPlayer decodes 8-bit progressive H.264 only, so anything else is re-encoded
            CodecProfile(
                codec: "h264",
                conditions: [
                    ProfileCondition(condition: .equalsAny, isRequired: false, property: .videoProfile, value: "high|main|baseline|constrained baseline"),
                    ProfileCondition(condition: .notEquals, isRequired: false, property: .isInterlaced, value: "true"),
                ],
                type: .video
            ),
            // AVPlayer plays HEVC only with the hvc1 or dvh1 tag
            CodecProfile(
                codec: "hevc",
                conditions: [
                    ProfileCondition(condition: .equalsAny, isRequired: true, property: .videoCodecTag, value: "hvc1|dvh1"),
                    ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoFramerate, value: "60"),
                ],
                type: .video
            ),
        ],
        directPlayProfiles: [
            DirectPlayProfile(audioCodec: "aac,ac3,eac3,alac,flac", container: "mp4,m4v,mov", type: .video, videoCodec: "h264,hevc"),
        ],
        maxStreamingBitrate: 120_000_000,
        subtitleProfiles: [
            // the app draws text subtitles from their files, timed in source time; bitmap ones are never offered,
            // since burning them in re-encodes the video
            SubtitleProfile(format: "vtt", method: .external),
            SubtitleProfile(format: "subrip", method: .external),
            SubtitleProfile(format: "srt", method: .external),
            SubtitleProfile(format: "ass", method: .external),
            SubtitleProfile(format: "ssa", method: .external),
            SubtitleProfile(format: "mov_text", method: .external),
        ],
        transcodingProfiles: [
            // fMP4, because Apple's HLS takes HEVC only there; copying the video starts in seconds where re-encoding 4K never kept up
            TranscodingProfile(
                protocol: .hls,
                audioCodec: "aac,ac3,eac3",
                container: "mp4",
                context: .streaming,
                enableSubtitlesInManifest: false,
                isBreakOnNonKeyFrames: true,
                maxAudioChannels: "6",
                minSegments: 2,
                type: .video,
                videoCodec: "h264,hevc"
            ),
        ]
    )
}
