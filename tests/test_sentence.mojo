# mojoui.sentence (goal 28 M1): plain runs and tokens on lines that wrap at a word's edge, never inside one; tokens are
# TOKEN buttons with their message and tag; the plain text reads as the sentence.
#   scripts/mxbuild.sh tests/test_sentence.mojo -o build/test_sentence && build/test_sentence
from std.testing import assert_equal, assert_true
from mojoui.view import BUTTON, TEXT, HSTACK, VSTACK, TOKEN
from mojoui.sentence import Word, Sentence, sentence_text


def words() -> List[Word]:
    return [Word("Sum", 10, "w0"), Word(" of "), Word("amount", 11, "w1"), Word(" by "), Word("region", 12, "w2"), Word(", "),
            Word("largest first", 13, "w3"), Word(", "), Word("top 5", 14, "w4")]


def main() raises:
    assert_equal(sentence_text(words()), "Sum of amount by region, largest first, top 5")
    var one = Sentence(words(), width=80)
    assert_equal(one.nodes[0].kind, VSTACK)
    assert_equal(len(one.nodes[0].children), 1, "it fits one line")
    var tokens = 0
    for n in one.nodes:
        if n.kind == BUTTON:
            assert_equal(n.style, TOKEN)
            tokens += 1
    assert_equal(tokens, 5)
    var narrow = Sentence(words(), width=24)
    var lines = len(narrow.nodes[0].children)
    assert_true(lines >= 2, "a narrow sentence wraps")
    var texts = List[String]()
    for i in range(len(narrow.nodes)):
        if narrow.nodes[i].kind == BUTTON or narrow.nodes[i].kind == TEXT:
            texts.append(narrow.nodes[i].text)
    var joined = String("")
    for t in texts:
        joined += t + "|"
    assert_true("largest first|" in joined, "a token is never split")
    for i in range(len(narrow.nodes)):
        if narrow.nodes[i].kind == HSTACK:  # (a line never starts with a space)
            var first = narrow.nodes[narrow.nodes[i].children[0]].text
            assert_true(not first.startswith(" "), "line starts with '" + first + "'")
    for n in narrow.nodes:
        if n.kind == BUTTON and n.text == "amount":
            assert_equal(n.msg, 11)
            assert_equal(n.name, "w1")
    print("SENTENCE TESTS PASSED")
