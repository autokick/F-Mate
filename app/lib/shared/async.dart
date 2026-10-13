import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// 비동기 로딩 화면 공통: 로딩 / 오류(다시 시도) / 빈 상태 / 데이터
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.empty,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  State<AsyncBody<T>> createState() => AsyncBodyState<T>();
}

class AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  ApiError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiError.from(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingState();
    if (_error != null && _data == null) return ErrorView(error: _error!, onRetry: reload);
    final data = _data as T;
    if (widget.isEmpty != null && widget.isEmpty!(data) && widget.empty != null) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [widget.empty!]),
      );
    }
    return widget.builder(context, data, reload);
  }
}

/// ApiError 를 상황에 맞는 화면으로
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final ApiError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error.isNotConfigured) {
      return EmptyState(icon: Icons.construction_rounded, title: '준비 중인 기능이에요', message: error.message);
    }
    if (error.status == 403) {
      return EmptyState(icon: Icons.lock_outline_rounded, title: '권한이 없어요', message: error.message);
    }
    if (error.status == 404) {
      return const EmptyState(icon: Icons.search_off_rounded, title: '찾을 수 없어요', message: '삭제되었거나 볼 수 없는 내용이에요.');
    }
    return ErrorState(
      title: error.isNetwork ? '연결할 수 없어요' : '문제가 생겼어요',
      message: error.message,
      onRetry: onRetry,
      icon: error.isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
    );
  }
}

/// 커서 기반 무한 스크롤 목록 + 당겨서 새로고침
class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.empty,
    this.header,
    this.padding,
    this.separator,
  });

  /// cursor 가 null 이면 첫 페이지. (items, nextCursor) 반환
  final Future<(List<T>, int?)> Function(int? cursor) fetch;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget empty;
  final Widget? header;
  final EdgeInsetsGeometry? padding;
  final Widget? separator;

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final List<T> items = [];
  int? _next;
  bool _hasMore = true;
  bool _loading = false;
  bool _initial = true;
  ApiError? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    _next = null;
    _hasMore = true;
    _error = null;
    try {
      final (list, next) = await widget.fetch(null);
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(list);
        _next = next;
        _hasMore = next != null;
        _initial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiError.from(e);
        _initial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _initial || _next == null) return;
    _loading = true;
    try {
      final (list, next) = await widget.fetch(_next);
      if (!mounted) return;
      setState(() {
        items.addAll(list);
        _next = next;
        _hasMore = next != null;
      });
    } catch (_) {
      // 다음 스크롤 때 다시 시도
    } finally {
      _loading = false;
    }
  }

  /// 목록 갱신 없이 항목 하나 제거 (삭제 등)
  void removeWhere(bool Function(T) test) => setState(() => items.removeWhere(test));

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    // 헤더(필터 등)는 로딩·오류 중에도 보이게 둔다
    if (_initial || (_error != null && items.isEmpty)) {
      final state = _initial ? const LoadingState() : ErrorView(error: _error!, onRetry: refresh);
      if (header == null) return state;
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [header, state]),
      );
    }
    final count = items.length + (header != null ? 1 : 0) + 1;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: count,
        itemBuilder: (context, i) {
          if (header != null && i == 0) return header;
          final idx = i - (header != null ? 1 : 0);
          if (idx == items.length) {
            if (items.isEmpty) return widget.empty;
            return _hasMore
                ? const Padding(
                    padding: EdgeInsets.all(FmSpace.l),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : const SizedBox(height: FmSpace.xl);
          }
          final item = widget.itemBuilder(context, items[idx], idx);
          if (widget.separator != null && idx > 0) {
            return Column(children: [widget.separator!, item]);
          }
          return item;
        },
      ),
    );
  }
}
