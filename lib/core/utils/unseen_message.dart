/// Whether an incoming message should raise the "scroll to bottom" badge.
/// Only a new message from the open contact counts, and only while the user
/// is scrolled away from the bottom.
bool shouldCountUnseen({
  required String peerPubkey,
  required String openPubkey,
  required bool nearBottom,
}) {
  if (nearBottom) return false;
  return peerPubkey == openPubkey;
}
