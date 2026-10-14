import 'package:flutter/material.dart';

class ProductSearchField extends StatefulWidget {
  const ProductSearchField({super.key, required this.onChanged, this.onSubmitted});
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  @override
  State<ProductSearchField> createState() => _ProductSearchFieldState();
}

class _ProductSearchFieldState extends State<ProductSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onSubmitted == null ? null : () {},
      onSubmitted: widget.onSubmitted == null ? null : (value) {
        final code = value.trim();
        if (code.isEmpty) return;
        widget.onSubmitted!(code);
        _controller.clear();
        widget.onChanged('');
        _focus.requestFocus();
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Search products or SKU',
        hintText: widget.onSubmitted == null ? 'Name or SKU' : 'Scan SKU, then press Enter',
        prefixIcon: const Icon(Icons.search),
        constraints: const BoxConstraints(minHeight: 48),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
