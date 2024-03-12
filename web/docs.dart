// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'highlight.dart' as highlight;
import 'search.dart' as search;
import 'sidebars.dart' as sidebars;
import 'theme.dart' as theme;

void main() {
  sidebars.init();
  search.init();
  highlight.init();
  theme.init();
}

void x() {
  var members = document.querySelectorAll('.main-content dt').reversed;
  print('found ${members.length} sections');
  var mainContent = document.querySelector('.main-content');
  if (mainContent == null) return;
  var title = document.querySelector('#title');
  if (title == null) return;
  var gap = title.offsetHeight;
  const margin = 16; // The approximate margin between members.
  mainContent.onScroll.listen((_) {
    var scrollTop = mainContent.scrollTop + gap + margin;
    for (var item in members) {
      var id = item.id;
      var navLink =
          document.querySelector('.sidebar-offcanvas-right li a[href="#$id"]');
      if (navLink != null) {
        navLink.classes.remove('active');
      }
    }
    for (var item in members) {
      var id = item.id;
      var navLink =
          document.querySelector('.sidebar-offcanvas-right li a[href="#$id"]');
      /*if (id.startsWith('i')) {
        print('id: $id; navlink: $navLink; $scrollTop ?> ${item.offsetTop}');
      }*/
      if (navLink == null) continue;
      if (scrollTop > item.offsetTop) {
        navLink.classes.add('active');
        return;
      }
    }
  });
}

void initializeSidebars() {
  final body = document.body;
  if (body == null) {
    return;
  }
  final dataUsingBaseHref = body.getAttribute('data-using-base-href');
  if (dataUsingBaseHref == null) {
    // This should never happen.
    return;
  }
  final String baseHref;
  if (dataUsingBaseHref != 'true') {
    final dataBaseHref = body.getAttribute('data-base-href');
    if (dataBaseHref == null) {
      return;
    }
    baseHref = dataBaseHref;
  } else {
    baseHref = '';
  }

  final mainContent = document.getElementById('dartdoc-main-content');
  if (mainContent == null) {
    return;
  }
  final sanitizer = _SidebarNodeTreeSanitizer(baseHref);

  void loadSidebar(String? sidebarPath, Element? sidebarElement) {
    if (sidebarPath == null || sidebarPath.isEmpty || sidebarElement == null) {
      return;
    }

    window.fetch('$baseHref$sidebarPath').then((response) async {
      final fetchResponse = response as FetchResponse;
      if (response.status != 200) {
        final errorAnchor = (document.createElement('a') as AnchorElement)
          ..href = 'https://dart.dev/tools/dart-doc#troubleshoot'
          ..text = 'Failed to load sidebar. '
              'Visit dart.dev for help troubleshooting.';
        sidebarElement.append(errorAnchor);
        return;
      }

      final content = await fetchResponse.text;

      sidebarElement.setInnerHtml(content, treeSanitizer: sanitizer);

      x();
    });
  }

  final aboveSidebarPath = mainContent.getAttribute('data-above-sidebar');
  final leftSidebar = document.getElementById('dartdoc-sidebar-left-content');
  loadSidebar(aboveSidebarPath, leftSidebar);

  final belowSidebarPath = mainContent.getAttribute('data-below-sidebar');
  final rightSidebar = document.getElementById('dartdoc-sidebar-right');
  loadSidebar(belowSidebarPath, rightSidebar);
}

/// A permissive sanitizer that allows external links (e.g. to api.dart.dev) and
/// adjusts the links in a newly loaded sidebar, if "base href" is not being
/// used.
class _SidebarNodeTreeSanitizer implements NodeTreeSanitizer {
  final String baseHref;

  _SidebarNodeTreeSanitizer(this.baseHref);

  @override
  void sanitizeTree(Node node) {
    if (node is Element && node.nodeName == 'A') {
      final hrefString = node.attributes['href'];
      if (hrefString != null && !hrefString.startsWith('#')) {
        final href = Uri.parse(hrefString);
        if (!href.isAbsolute) {
          node.setAttribute('href', '$baseHref$hrefString');
        }
      }
    }
    node.childNodes.forEach(sanitizeTree);
  }
}
