import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/http/black.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/blacklist/data.dart';
import 'package:PiliPlus/models_new/blacklist/list.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class BlackListController
    extends CommonListController<BlackListData, BlackListItem> {
  int? _total;
  final blackMids = GlobalData().blackMids;

  void addBlackMids(Iterable<int> mids) {
    blackMids.addAll(mids.where((mid) => mid > 0));
    Pref.blackMids = blackMids;
  }

  bool removeBlackMid(int mid) {
    final removed = blackMids.remove(mid);
    if (removed) Pref.blackMids = blackMids;
    return removed;
  }

  /// 拉取账号侧完整在线黑名单，并与本地投稿过滤名单合并后导出。
  Future<Set<int>> collectAllBlackMidsForExport() async {
    final mids = Set<int>.of(blackMids);
    if (!Accounts.main.isLogin) return mids;

    var loaded = 0;
    int? total;
    for (var pn = 1; pn <= 1000; pn++) {
      final result = await BlackHttp.blackList(pn: pn);
      if (result case Success(:final response)) {
        final items = response.list ?? const <BlackListItem>[];
        mids.addAll(
          items.map((item) => item.mid).whereType<int>().where((mid) => mid > 0),
        );
        loaded += items.length;
        total = response.total ?? total;
        if (items.isEmpty && total != null && loaded < total) {
          throw StateError('在线黑名单数量异常，已读取 $loaded/$total 项');
        }
        if (items.isEmpty || (total != null && loaded >= total)) {
          blackMids.addAll(mids);
          Pref.blackMids = blackMids;
          return mids;
        }
      } else {
        throw StateError(result.toString());
      }
    }

    final progress = total == null ? '$loaded 项' : '$loaded/$total 项';
    throw StateError('在线黑名单分页超过安全上限，已读取 $progress');
  }

  @override
  void onInit() {
    super.onInit();
    if (Accounts.main.isLogin) {
      queryData();
    } else {
      loadingState.value = const Error('账号未登录');
    }
  }

  @override
  List<BlackListItem>? getDataList(BlackListData response) {
    _total = response.total;
    return response.list;
  }

  @override
  void checkIsEnd(int length) {
    if (_total != null && length >= _total!) {
      isEnd = true;
    }
  }

  Future<bool> onRemove(BuildContext context, int index, name, mid) async {
    final confirm = await showConfirmDialog(
      context: context,
      title: Text('确定将 $name 移出黑名单？'),
    );
    if (confirm) {
      final result = await VideoHttp.relationMod(mid: mid, act: 6, reSrc: 11);
      if (result.isSuccess) {
        loadingState
          ..value.data!.removeAt(index)
          ..refresh();
        _total -= 1;
        SmartDialog.showToast('移除成功');
        return true;
      }
    }
    return false;
  }

  @override
  Future<LoadingState<BlackListData>> customGetData() =>
      BlackHttp.blackList(pn: page);

  @override
  void onClose() {
    super.onClose();
    if (loadingState.value case Success(:final response?)) {
      blackMids.addAll(response.map((e) => e.mid!));
    }
    Pref.blackMids = blackMids;
  }
}

Set<int> parseBlackMids(Iterable<Object?> values) {
  final mids = <int>{};
  var index = 0;
  for (final value in values) {
    index++;
    final int? mid;
    if (value is int) {
      mid = value;
    } else if (value is String) {
      mid = int.tryParse(value.trim());
    } else {
      mid = null;
    }
    if (mid == null || mid <= 0) {
      throw FormatException('第 $index 项不是有效的正整数 UID');
    }
    mids.add(mid);
  }
  return mids;
}
