import 'dart:math';
import 'dart:math' as Math;
import 'package:flutter/widgets.dart';

enum SwiperPosition { None, Left, Right }
enum StackFrom { None, Top, Left, Right, Bottom }

class SwiperItem<T> {
  T item;
  Widget Function(T item, SwiperPosition position, double progress) builder;

  SwiperItem({@required this.item, @required this.builder});
}

class SwipeStack<T> extends StatefulWidget {
  //final List<SwiperItem> children;

  final Future<List<T>> Function() getItems;
  final int minItemCount;
  final int maxAngle;
  final int threshold;
  final StackFrom stackFrom;
  final int visibleCount;
  final int translationInterval;
  final double scaleInterval;
  final Duration animationDuration;
  final int historyCount;
  final Widget Function(T item, SwiperPosition position, double progress)
      itemBuilder;
  final void Function(T item, int, SwiperPosition) onSwipe;
  final void Function(T item, int, SwiperPosition) onRewind;
  final void Function() onEnd;
  final EdgeInsetsGeometry padding;

  SwipeStack(
      {Key key,
      @required this.getItems,
      @required this.itemBuilder,
      this.minItemCount = 3,
      this.maxAngle = 35,
      this.threshold = 30,
      this.stackFrom = StackFrom.None,
      this.visibleCount = 2,
      this.translationInterval = 0,
      this.scaleInterval = 0,
      this.animationDuration = const Duration(milliseconds: 200),
      this.historyCount = 1,
      this.onEnd,
      this.onSwipe,
      this.onRewind,
      this.padding = const EdgeInsets.symmetric(vertical: 20, horizontal: 25)})
      : assert(maxAngle >= 0 && maxAngle <= 360),
        assert(threshold >= 1 && threshold <= 100),
        assert(visibleCount >= 2),
        assert(translationInterval >= 0),
        assert(scaleInterval >= 0),
        assert(historyCount >= 0),
        super(key: key);

  SwipeStackState createState() => SwipeStackState();
}

class SwipeStackState<T> extends State<SwipeStack<T>>
    with SingleTickerProviderStateMixin {
  List<SwiperItem<T>> children = [];

  AnimationController _animationController;
  Animation<double> _animationX;
  Animation<double> _animationY;
  Animation<double> _animationAngle;

  double _left = 0;
  double _top = 0;
  double _angle = 0;
  double _maxAngle = 0;
  double _progress = 0;
  double _centerSlow = 1;
  SwiperPosition _currentItemPosition = SwiperPosition.None;
  final List<Map<String, dynamic>> _history = [];

  final Map<StackFrom, Alignment> _alignment = {
    StackFrom.Left: Alignment.centerLeft,
    StackFrom.Top: Alignment.topCenter,
    StackFrom.Right: Alignment.centerRight,
    StackFrom.Bottom: Alignment.bottomCenter,
    StackFrom.None: Alignment.center
  };

  bool _isTop = false;
  bool _isLeft = false;

  int _animationType = 0;
  // 0 None, 1 move, 2 manuel, 3 rewind

  BoxConstraints _baseContainerConstraints;

  int get currentIndex => children.length - 1;

  void addItems(List<T> items) {
    items.removeWhere((element) => children.contains(element));
    children = [
      ...items
          .map((e) => SwiperItem<T>(item: e, builder: widget.itemBuilder))
          .toList(),
      ...children
    ];
  }

  @override
  void initState() {
    children = [];

    widget.getItems().then((List<T> items) {
      setState(() {
        addItems(items);
      });
    });

    if (widget.maxAngle > 0) _maxAngle = widget.maxAngle * (Math.pi / 180);

    _animationController =
        AnimationController(duration: widget.animationDuration, vsync: this);

    _animationController.addListener(() {
      if (_animationController.status == AnimationStatus.forward) {
        if (_animationX != null) _left = _animationX.value;

        if (_animationY != null) _top = _animationY.value;

        if (_animationType != 1 && _animationAngle != null)
          _angle = _animationAngle.value;

        _progress = (100 / _baseContainerConstraints.maxWidth) * _left.abs();
        _currentItemPosition = (_left.toInt() == 0)
            ? SwiperPosition.None
            : (_left < 0)
                ? SwiperPosition.Left
                : SwiperPosition.Right;

        setState(() {});
      }
    });

    _animationController
        .addStatusListener((AnimationStatus animationStatus) async {
      if (animationStatus == AnimationStatus.completed) {
        // history
        if (_animationType != 3 && _animationType != 0) {
          if (widget.historyCount > 0) {
            _history.add({
              "item": children[children.length - 1],
              "position": _currentItemPosition,
              "left": _left,
              "top": _top,
              "angle": _angle
            });

            if (_history.length > widget.historyCount) _history.removeAt(0);
          }
        } else if (_animationType == 3) {
          if (widget.onRewind != null)
            widget.onRewind(
                (_history[_history.length - 1]["item"] as SwiperItem<T>).item,
                children.length - 1,
                _history[_history.length - 1]["position"]);
          _history.removeAt(_history.length - 1);
        }

        if (_animationType != 0 && _animationType != 3) {
          SwiperItem<T> item = children.removeAt(children.length - 1);

          if (widget.onSwipe != null)
            widget.onSwipe(item.item, children.length, _currentItemPosition);

          if (children.length <= widget.minItemCount) {
            widget.getItems().then((value) {
              addItems(value);
            });
          }

          if (children.length == 0 && widget.onEnd != null) widget.onEnd();
        }

        _left = 0;
        _top = 0;
        _angle = 0;
        _progress = 0;
        _currentItemPosition = SwiperPosition.None;
        _animationType = 0;
        setState(() {});
        _animationController.reset();
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      _baseContainerConstraints = constraints;

      if (children.length == 0) return Container();

      return Container(
        padding: widget.padding,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              //overflow: Overflow.visible,
              fit: StackFit.expand,
              children: children
                  .asMap()
                  .map((int index, _) {
                    return MapEntry(index, _item(constraints, index));
                  })
                  .values
                  .toList(),
            );
          },
        ),
      );
    });
  }

  Widget _item(BoxConstraints constraints, int index) {
    if (index != children.length - 1) {
      double scaleReduced = (widget.scaleInterval * (children.length - index));
      scaleReduced -= ((widget.scaleInterval * 2) / 100) * _progress;
      final double scale = 1 - scaleReduced;

      double positionReduced =
          ((widget.translationInterval * (children.length - index - 1)))
              .toDouble();
      positionReduced -= (widget.translationInterval / 100) * _progress;
      final double position = positionReduced * -1;

      return Visibility(
        visible: (children.length - index) <= widget.visibleCount,
        child: Positioned(
            top: widget.stackFrom == StackFrom.Top ? position : null,
            left: widget.stackFrom == StackFrom.Left ? position : null,
            right: widget.stackFrom == StackFrom.Right ? position : null,
            bottom: widget.stackFrom == StackFrom.Bottom ? position : null,
            child: Transform.scale(
                scale: scale,
                alignment: _alignment[widget.stackFrom],
                child: Container(
                    constraints: constraints,
                    child: children[index].builder(
                        children[index].item, SwiperPosition.None, 0)))),
      );
    }

    if (widget.maxAngle > 0 &&
        _animationController.status != AnimationStatus.forward) {
      _angle = ((_maxAngle / 100) * _progress) * _centerSlow;
      _angle = _angle *
          ((_isTop && _isLeft)
              ? 1
              : (!_isTop && !_isLeft)
                  ? 1
                  : -1);
    }

    return Positioned(
      left: _left,
      top: _top,
      child: GestureDetector(
          child: Transform.rotate(
            angle: _angle,
            child: Container(
                constraints: constraints,
                child: children[index].builder(
                    children[index].item, _currentItemPosition, _progress)),
          ),
          onPanStart: (DragStartDetails dragStartDetails) {
            RenderBox getBox = context.findRenderObject();
            var local = getBox.globalToLocal(dragStartDetails.globalPosition);

            _isLeft = local.dx < getBox.size.width / 2;
            _isTop = local.dy < getBox.size.height / 2;

            double halfHeight = getBox.size.height / 2;
            _centerSlow = ((halfHeight - local.dy) * (1 / halfHeight)).abs();
          },
          onPanUpdate: (DragUpdateDetails dragUpdateDetails) {
            _left += dragUpdateDetails.delta.dx;
            // _top += dragUpdateDetails.delta.dy;

            _progress =
                (100 / _baseContainerConstraints.maxWidth) * _left.abs();
            _currentItemPosition = (_left.toInt() == 0)
                ? SwiperPosition.None
                : (_left < 0)
                    ? SwiperPosition.Left
                    : SwiperPosition.Right;
            setState(() {});
          },
          onPanEnd: _onPandEnd),
    );
  }

  void _onPandEnd(_) {
    setState(() {});
    if (_progress < widget.threshold) {
      _goFirstPosition();
    } else {
      //_animationController.duration = Duration(milliseconds: 100);
      _animationController.duration =
          Duration(milliseconds: max(400 - (4 * _progress.toInt()), 200));
      _animationType = 1;
      _animationX = Tween<double>(
              begin: _left,
              end: _baseContainerConstraints.maxWidth * (_left < 0 ? -1 : 1))
          .animate(_animationController);
      //_animationY = Tween<double>(begin: _top, end: _top + _top).animate(_animationController);
      _animationController.forward();
    }
  }

  void _goFirstPosition() {
    _animationX =
        Tween<double>(begin: _left, end: 0.0).animate(_animationController);
    _animationY =
        Tween<double>(begin: _top, end: 0.0).animate(_animationController);
    if (widget.maxAngle > 0)
      _animationAngle =
          Tween<double>(begin: _angle, end: 0.0).animate(_animationController);
    _animationController.forward();
  }

  void swipeLeft() {
    if (children.length > 0 &&
        _animationController.status != AnimationStatus.forward) {
      _animationController.duration = widget.animationDuration;
      _animationType = 2;
      _animationX =
          Tween<double>(begin: 0, end: _baseContainerConstraints.maxWidth * -1)
              .animate(_animationController);
      //  _animationY = Tween<double>(begin: 0, end: (_baseContainerConstraints.maxHeight / 2) * -1).animate(_animationController);
      if (widget.maxAngle > 0)
        _animationAngle = Tween<double>(begin: 0, end: _maxAngle * 0.35)
            .animate(_animationController);
      _animationController.forward();
    }
  }

  void swipeRight() {
    if (children.length > 0 &&
        _animationController.status != AnimationStatus.forward) {
      _animationController.duration = widget.animationDuration;
      _animationType = 2;
      _animationX =
          Tween<double>(begin: 0, end: _baseContainerConstraints.maxWidth)
              .animate(_animationController);
      // _animationY = Tween<double>(begin: 0, end: (_baseContainerConstraints.maxHeight / 2) * -1).animate(_animationController);
      if (widget.maxAngle > 0)
        _animationAngle = Tween<double>(begin: 0, end: (_maxAngle * 0.35) * -1)
            .animate(_animationController);
      _animationController.forward();
    }
  }

  void rewind() {
    if (_history.length > 0 &&
        _animationController.status != AnimationStatus.forward) {
      _animationType = 3;
      _animationController.duration = widget.animationDuration;

      final lastHistory = _history[_history.length - 1];

      children.add(lastHistory["item"]);
      _animationX = Tween<double>(begin: lastHistory["left"], end: 0)
          .animate(_animationController);
      _animationY = Tween<double>(begin: lastHistory["top"], end: 0)
          .animate(_animationController);
      if (widget.maxAngle > 0)
        _animationAngle = Tween<double>(begin: lastHistory["angle"], end: 0)
            .animate(_animationController);

      _animationController.forward();
    }
  }

  void clearHistory() => _history.clear();

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
