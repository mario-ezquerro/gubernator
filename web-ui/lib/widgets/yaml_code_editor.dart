import 'package:flutter/material.dart';

/// A code editor widget for Docker Compose YAML with line numbers toggle and synchronized scrolling.
class YamlCodeEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool showLineNumbers;
  final ValueChanged<bool> onToggleLineNumbers;
  final String? Function(String?)? validator;
  final bool isDark;
  final FocusNode? focusNode;

  const YamlCodeEditor({
    super.key,
    required this.controller,
    required this.showLineNumbers,
    required this.onToggleLineNumbers,
    required this.isDark,
    this.validator,
    this.focusNode,
  });

  @override
  State<YamlCodeEditor> createState() => _YamlCodeEditorState();
}

class _YamlCodeEditorState extends State<YamlCodeEditor> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final lines = text.isEmpty ? 1 : text.split('\n').length;
    final lineNumbersText = List.generate(lines, (i) => '${i + 1}').join('\n');

    final textColor = widget.isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1E293B);
    final lineNumberColor = widget.isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B);
    final gutterBg = widget.isDark ? const Color(0xFF161B22) : const Color(0xFFE2E8F0);
    final editorBg = widget.isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC);
    final borderColor = widget.isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1);

    const textStyle = TextStyle(
      fontFamily: 'Courier New',
      fontSize: 13,
      height: 1.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editor Toolbar / Header with Line Numbers Toggle
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 16,
                    color: widget.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'YAML Editor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: lineNumberColor,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => widget.onToggleLineNumbers(!widget.showLineNumbers),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        widget.showLineNumbers ? Icons.format_list_numbered_rounded : Icons.format_list_bulleted_rounded,
                        size: 16,
                        color: widget.showLineNumbers ? (widget.isDark ? const Color(0xFF58A6FF) : const Color(0xFF2563EB)) : lineNumberColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Line Numbers',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: widget.showLineNumbers ? FontWeight.w600 : FontWeight.normal,
                          color: widget.showLineNumbers ? (widget.isDark ? const Color(0xFF58A6FF) : const Color(0xFF2563EB)) : lineNumberColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: widget.showLineNumbers,
                        onChanged: widget.onToggleLineNumbers,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeThumbColor: const Color(0xFF58A6FF),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Text Field & Optional Line Numbers Gutter
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: editorBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border(
                left: BorderSide(color: borderColor),
                right: BorderSide(color: borderColor),
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Line Numbers Gutter
                if (widget.showLineNumbers)
                  Container(
                    width: lines > 999 ? 54 : 44,
                    color: gutterBg,
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                    decoration: BoxDecoration(
                      color: gutterBg,
                      border: Border(right: BorderSide(color: borderColor)),
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        lineNumbersText,
                        textAlign: TextAlign.right,
                        style: textStyle.copyWith(color: lineNumberColor),
                      ),
                    ),
                  ),

                // Main YAML TextFormField
                Expanded(
                  child: TextFormField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: _scrollController,
                    maxLines: null,
                    expands: true,
                    style: textStyle.copyWith(color: textColor),
                    decoration: const InputDecoration(
                      fillColor: Colors.transparent,
                      filled: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                    validator: widget.validator,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
