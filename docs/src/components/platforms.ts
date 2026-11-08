// The three apps in the order the switcher and the "Also on" cards list them (icons draw in a 24-unit box)
export const platforms = [
  {
    key: "iphone",
    name: "iPhone",
    path: "iphone/",
    tagline: "Track, discover and play",
    icon: '<rect x="7" y="2.5" width="10" height="19" rx="2.2"/><path d="M11 18.5h2"/>',
  },
  {
    key: "mac",
    name: "Mac",
    path: "mac/",
    tagline: "Browse and watch",
    icon: '<rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/>',
  },
  {
    key: "tv",
    name: "Apple TV",
    path: "apple-tv/",
    tagline: "Relax and watch",
    icon: '<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8 20.5h8"/>',
  },
] as const;

export type Platform = (typeof platforms)[number]["key"];
