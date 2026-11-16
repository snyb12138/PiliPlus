import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class VideoPurifyHomeController extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final ScrollController scrollController = ScrollController();

  @override
  Future<void> onRefresh() => Future<void>.value();

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
