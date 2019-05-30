part of universal_html;

bool _matches(Element element, String selector, String pseudoElement) {
  if (selector == null) {
    throw ArgumentError.notNull(selector);
  }
  if (selector.isEmpty) {
    throw DomException._("invalidSelector", "Selector can't be blank");
  }
  final selectorGroup = css.parseSelectorGroup(selector);
  if (selectorGroup == null) {
    throw DomException._(
        "invalidSelector", "Selector could not be parsed: '$selector'");
  }
  return _matchesSelectorGroup(element, selectorGroup, null);
}

bool _matchesSelector(
    Element element, css.Selector selector, int index, String pseudoElement) {
  final simpleSelectorSequences = selector.simpleSelectorSequences;
  if (simpleSelectorSequences.isEmpty) {
    throw ArgumentError();
  }
  final simpleSelectorSequence = simpleSelectorSequences[index];
  if (!_matchesSimpleSelector(
      element, simpleSelectorSequence.simpleSelector, pseudoElement)) {
    return false;
  }

  // Move to the next simple selector
  index--;

  // If there are no more simple selectors
  if (index < 0) {
    return true;
  }

  // What combinator we have?
  final combinator = simpleSelectorSequence.combinator;
  switch (combinator) {
    //
    // s0.s1:s2
    //
    case css.TokenKind.COMBINATOR_NONE:
      return _matchesSelector(element, selector, index, pseudoElement);

    //
    // s0 s1 s2
    //
    case css.TokenKind.COMBINATOR_DESCENDANT:
      // We try all parents
      Node node = element.parent;
      while (node != null) {
        if (node is Element &&
            _matchesSelector(node, selector, index, pseudoElement)) {
          return true;
        }
        node = node.parent;
      }
      return false;

    //
    // s0 > s1 > s2
    //
    case css.TokenKind.COMBINATOR_GREATER:
      // We try only immediate parent
      final parent = element.parent;
      if (parent == null) {
        return false;
      }
      return _matchesSelector(parent, selector, index, pseudoElement);

    //
    // s0 ~ s1 ~ s2
    //
    case css.TokenKind.COMBINATOR_TILDE:
      // We try only immediate parent
      while (true) {
        element = element.previousElementSibling;
        if (element == null) {
          return false;
        }
        if (_matchesSelector(
          element,
          selector,
          index,
          pseudoElement,
        )) {
          return true;
        }
      }
      break;

    //
    // s0 + s1 + s2
    //
    case css.TokenKind.COMBINATOR_PLUS:
      // We try only immediate parent
      final previous = element.previousElementSibling;
      if (previous == null) {
        return false;
      }
      return _matchesSelector(previous, selector, index, pseudoElement);

    default:
      throw UnsupportedError(
          "Unsupported combinator ${combinator} in '${simpleSelectorSequence.span.text}'");
  }
}

// We start from the innermost selector.
//
// Example:
//   "#a < .b .c"
//     1.We match '.c'
//     2.We try each parent that matches '.b'
//     3.We match immediate parent for '#a'
bool _matchesSelectorGroup(
    Element element, css.SelectorGroup selectorGroup, String pseudoElement) {
  if (selectorGroup == null) {
    throw ArgumentError.notNull();
  }
  final selectors = selectorGroup.selectors;
  if (selectors.isEmpty) {
    throw ArgumentError();
  }
  for (var selector in selectors) {
    if (_matchesSelector(element, selector,
        selector.simpleSelectorSequences.length - 1, pseudoElement)) {
      return true;
    }
  }
  return false;
}

bool _matchesSimpleSelector(
    Element element, css.SimpleSelector selector, String pseudoElement) {
  if (selector.isWildcard) {
    return true;
  } else if (selector is css.ElementSelector) {
    //
    // elementName
    //
    return selector.name.toLowerCase() == element._lowerCaseTagName;
  } else if (selector is css.IdSelector) {
    //
    // #id
    //
    return element.id == selector.name;
  } else if (selector is css.ClassSelector) {
    //
    // .className
    //
    final className = element.className;
    if (className == null || className.isEmpty) return false;
    final expected = selector.name;
    if (className.contains(" ")) {
      return className.split(" ").contains(expected);
    } else {
      return className == expected;
    }
  } else if (selector is css.NegationSelector) {
    //
    // :not(selector)
    //
    return !_matchesSimpleSelector(
        element, selector.negationArg, pseudoElement);
  } else if (selector is css.PseudoClassSelector) {
    //
    // :somePseudoSelector
    //
    switch (selector.name) {
      case "disabled":
        return element.getAttribute("disabled") != null;
      case "first-child":
        return identical(element.parent?.firstChild, element);
      case "last-child":
        return element.parent != null && element.nextNode == null;
      case "only-child":
        return element.nextElementSibling == null &&
            element.previousElementSibling == null;
      case "root":
        return element is HtmlHtmlElement;
      case "nth-child":
        if (selector is css.PseudoClassFunctionSelector) {
          return _matchesNthChildSelector(element, selector);
        } else {
          throw ArgumentError(selector);
        }
    }
  } else if (selector is css.PseudoElementSelector) {
    return pseudoElement != null && pseudoElement == selector.name;
  } else if (selector is css.PseudoElementFunctionSelector) {
    return false;
  } else if (selector is css.AttributeSelector) {
    String actualValue = element.getAttribute(selector.name);
    if (actualValue == null) {
      return false;
    }

    String expectationValue = selector.value as String;

    // Note: Csslib doesn't seem support case-insensitive attributes
    // like '[name="value" i]'
    switch (selector.operatorKind) {
      //
      // [name="value"]
      //
      case css.TokenKind.EQUALS:
        return actualValue == expectationValue;

      //
      // [name~="value"]
      //
      case css.TokenKind.INCLUDES:
        return actualValue.split(" ").contains(expectationValue);

      //
      // [name|="value"]
      //
      case css.TokenKind.DASH_MATCH:
        final length = expectationValue.length;
        return actualValue.startsWith(expectationValue) &&
            (actualValue.length == length ||
                actualValue.startsWith("-", length));

      //
      // [name^="value"]
      //
      case css.TokenKind.PREFIX_MATCH:
        return actualValue.startsWith(expectationValue);

      //
      // [name$="value"]
      //
      case css.TokenKind.SUFFIX_MATCH:
        return actualValue.endsWith(expectationValue);

      //
      // [name*="value"]
      //
      case css.TokenKind.SUBSTRING_MATCH:
        return actualValue.contains(expectationValue);

      //
      // [name]
      //
      case css.TokenKind.NO_MATCH:
        return true;
    }
  }
  throw _UnsupportedCssSelectorException(selector.span.text);
}

bool _matchesNthChildSelector(
    Element element, css.PseudoClassFunctionSelector selector) {
  // Find index of this node
  var index = 0;
  for (var sibling in element.parent.childNodes) {
    if (identical(sibling, element)) {
      break;
    }
    if (sibling is Element) {
      index++;
    }
  }

  // Get arguments
  final expressions = (selector.argument as css.SelectorExpression).expressions;

  // Choose based on the number of arguments
  switch (expressions.length) {
    case 1:
      //
      // :nth-child(3) | :nth-child(even) | :nth-child(odd)
      //
      final term0 = expressions[0];
      if (term0 is css.NumberTerm) {
        //
        // :nth-child(3)
        //
        final expectedIndex = (term0.value as num).toInt() - 1;
        return expectedIndex == index;
      } else if (term0 is css.LiteralTerm) {
        switch (term0.text) {
          case "even":
            //
            // :nth-child(even)
            //
            return index % 2 == 0;
          case "odd":
            //
            // :nth-child(odd)
            //
            return index % 2 == 1;
        }
      }
      throw _UnsupportedCssSelectorException(selector.span.text);

    case 2:
      //
      // nth-child(3n)
      //
      final term0 = expressions[0] as css.NumberTerm;
      final term1 = expressions[1] as css.LiteralTerm;
      assert(term1.text == "n");

      final mod = (term0.value as num).toInt();
      return (index % mod) == 1;

    case 3:
      //
      // :nth-child(3n+1)
      //
      final term0 = expressions[0] as css.NumberTerm;
      final term1 = expressions[1] as css.LiteralTerm;
      final term2 = expressions[2] as css.NumberTerm;
      assert(term1.text == "n");

      final mod = (term0.value as num).toInt();
      final rem = (term2.value as num).toInt();
      return (index % mod) == (rem - 1);
    default:
      throw _UnsupportedCssSelectorException(selector.span.text);
  }
}

class _UnsupportedCssSelectorException implements Exception {
  final String selector;

  _UnsupportedCssSelectorException(this.selector);

  @override
  String toString() =>
      "Unsupported (possibly valid) CSS selector: '${selector}'";
}