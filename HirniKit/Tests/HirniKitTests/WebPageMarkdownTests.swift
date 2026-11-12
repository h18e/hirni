import HirniKit
import Testing

struct WebPageMarkdownTests {
    typealias N = WebPageMarkdown.Node

    private func t(_ s: String) -> N { N(text: s) }

    @Test func headingsParagraphsAndInlineFormats() {
        let root = N("article", [
            N("h1", [t("Titel")]),
            N("p", [t("Ein "), N("strong", [t("fetter ")]), t("und "), N("em", [t("kursiver")]), t(" Text.")]),
            N("p", [t("Mehr "), N("a", href: "https://example.com/x", [t("dazu")]), t(".")]),
        ])
        #expect(WebPageMarkdown.markdown(from: root) == """
        # Titel

        Ein **fetter** und *kursiver* Text.

        Mehr dazu.
        """)
    }

    @Test func keepsLinksThatStandAlone() {
        let root = N("ul", [
            N("li", [t(" "), N("a", href: "https://example.com/a", [t("Seite A")]), t(" ")]),
            N("li", [t("Siehe "), N("a", href: "https://example.com/b", [t("B")])]),
        ])
        #expect(WebPageMarkdown.markdown(from: root) == "- [Seite A](https://example.com/a)\n- Siehe B")
    }

    @Test func nestedListsAndNumbers() {
        let root = N("div", [
            N("ul", [
                N("li", [t("Eins")]),
                N("li", [t("Zwei"), N("ol", [N("li", [t("a")]), N("li", [t("b")])])]),
            ]),
        ])
        #expect(WebPageMarkdown.markdown(from: root) == "- Eins\n- Zwei\n  1. a\n  2. b")
    }

    @Test func tablesQuotesAndCode() {
        let root = N("div", [
            N("table", [N("tbody", [
                N("tr", [N("th", [t("Name")]), N("th", [t("Preis")])]),
                N("tr", [N("td", [t("Brot")]), N("td", [t("3.50")])]),
            ])]),
            N("blockquote", [N("p", [t("Zitat")])]),
            N("pre", [N("code", [t("let a = 1\nlet b = 2")])]),
        ])
        #expect(WebPageMarkdown.markdown(from: root) == """
        | Name | Preis |
        | --- | --- |
        | Brot | 3.50 |

        > Zitat

        ```
        let a = 1
        let b = 2
        ```
        """)
    }

    @Test func looseTextBetweenBlocksBecomesParagraphs() {
        let root = N("div", [t("Vorher  \n  Text"), N("p", [t("Absatz")]), t("Nachher"), N("br"), t("Zeile")])
        #expect(WebPageMarkdown.markdown(from: root) == "Vorher Text\n\nAbsatz\n\nNachher\nZeile")
    }

    @Test func dropsFootnoteMarkers() {
        let root = N("p", [t("Satz."), N("sup", [N("a", href: "https://x.ch/#cite-1", [t("[1]")])]), t(" Weiter.")])
        #expect(WebPageMarkdown.markdown(from: root) == "Satz. Weiter.")
    }

    @Test func readsScriptResult() throws {
        let page = try WebPageMarkdown.page(fromJSON: #"{"title":"Seite","root":{"g":"p","c":[{"t":"Hallo"}]}}"#)
        #expect(page.title == "Seite")
        #expect(WebPageMarkdown.markdown(from: page.root) == "Hallo")
    }
}
