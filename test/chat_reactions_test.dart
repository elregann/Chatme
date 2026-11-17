import 'package:chatme/core/constants/chat_reactions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every category has emojis and repeats none of them', () {
    for (final category in ChatReactions.categories) {
      expect(category.emojis, isNotEmpty, reason: category.name);
      expect(
        category.emojis.toSet().length,
        category.emojis.length,
        reason: '${category.name} repeats an emoji',
      );
    }
  });

  test('the quick reactions are unique and offered in Popular', () {
    const quick = ChatReactions.defaultQuickReactions;
    expect(quick.toSet().length, quick.length);

    final popular = ChatReactions.categories
        .firstWhere((category) => category.name == 'Popular')
        .emojis;
    for (final emoji in quick) {
      expect(popular, contains(emoji));
    }
  });
}
