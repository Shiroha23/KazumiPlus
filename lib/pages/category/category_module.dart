import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/category/category_controller.dart';
import 'package:kazumi/pages/category/category_page.dart';

final categoryModule = createModule(
  path: '/category',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.material,
      child: (context, state) =>
          CategoryPage(controller: inject<CategoryController>()),
    );
  },
);
