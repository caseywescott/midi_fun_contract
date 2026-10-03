// BeatSync build switch.
//   true   stored onchain in the page, after the player: animated GIF art steps with the music
//   false  the page ships without it; a client can still inject dist/beatsync.min.js before the
//          page's DOMContentLoaded (or call BeatSync.attach itself) to get the same behaviour
export const BEATSYNC_ONCHAIN = true;
