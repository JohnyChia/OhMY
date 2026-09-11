import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCodeField extends StatefulWidget {
  const OtpCodeField({required this.controller, this.onSubmitted, super.key});

  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final activeIndex = code.length.clamp(0, 5);

    return GestureDetector(
      onTap: _focusNode.requestFocus,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Row(
              children: List.generate(6, (index) {
                final isActive = _focusNode.hasFocus && index == activeIndex;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index < code.length
                          ? Colors.white
                          : const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF2E60C4)
                            : const Color(0xFFC4D5F8),
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      index < code.length ? code[index] : '',
                      style: const TextStyle(
                        color: Color(0xFF17243D),
                        fontSize: 22,
                      ),
                    ),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => widget.onSubmitted?.call(),
                style: const TextStyle(color: Colors.transparent),
                cursorColor: Colors.transparent,
                decoration: const InputDecoration(
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
