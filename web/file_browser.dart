import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_mymc/dart_mymc.dart';
import 'package:mymc_web/card_image.dart';
import 'package:web/web.dart' as web;

/// File navigation uses native buttons, checkboxes, and keyboard focus.
class FileBrowser {
  final Ps2Card Function() card;
  final String Function() cardName;
  final void Function(String, Uint8List, bool) download;
  final void Function(String) onError;
  final void Function(String) onSaveActions;
  String _path = '';
  List<CardEntry> _entries = [];
  final Set<String> _selected = {};
  final Map<String, web.HTMLTableRowElement> _rows = {};
  final Map<String, web.HTMLInputElement> _checkboxes = {};

  FileBrowser({
    required this.card,
    required this.cardName,
    required this.download,
    required this.onError,
    required this.onSaveActions,
  }) {
    _button('folder-up').onClick.listen((_) => up());
    _filter.onInput.listen((_) {
      _selected.clear();
      _renderRows();
    });
    _selectAll.onChange.listen((_) {
      _selected.clear();
      if (_selectAll.checked) {
        _selected.addAll(_visible.map((entry) => entry.path));
      }
      _updateSelection();
    });
    _button('clear-file-selection').onClick.listen((_) {
      _selected.clear();
      _updateSelection();
    });
    _button('download-selection').onClick.listen((_) => _downloadSelection());
  }

  web.HTMLButtonElement _button(String id) =>
      web.document.getElementById(id)! as web.HTMLButtonElement;
  web.HTMLInputElement get _filter =>
      web.document.getElementById('file-filter')! as web.HTMLInputElement;
  web.HTMLInputElement get _selectAll =>
      web.document.getElementById('select-all-files')! as web.HTMLInputElement;
  List<CardEntry> get _visible => _entries
      .where(
        (entry) =>
            entry.name.toLowerCase().contains(_filter.value.toLowerCase()),
      )
      .toList();

  void reset() {
    _path = '';
    _entries = [];
    _selected.clear();
    _filter.value = '';
  }

  void show() => _navigate(_path);

  void up() {
    if (_path.isEmpty) return;
    final parts = _path.split('/')..removeLast();
    _navigate(parts.join('/'));
  }

  void _navigate(String path) {
    try {
      final entries = CardImage.listDirectory(card(), path);
      _entries = entries;
      _path = path;
      _selected.clear();
      _filter.value = '';
      _renderBreadcrumbs();
      _renderRows();
    } catch (e) {
      onError('Could not open folder: $e');
    }
  }

  web.HTMLButtonElement _action(
    String label,
    void Function() action, {
    String className = 'file-action',
  }) {
    final button =
        web.document.createElement('button') as web.HTMLButtonElement;
    button.type = 'button';
    button.className = className;
    button.textContent = label;
    button.onClick.listen((_) => action());
    return button;
  }

  void _renderBreadcrumbs() {
    final breadcrumbs = web.document.getElementById('file-breadcrumbs')!;
    breadcrumbs.textContent = '';
    breadcrumbs.appendChild(_action('Card root', () => _navigate('')));
    final parts = _path.isEmpty ? <String>[] : _path.split('/');
    for (var i = 0; i < parts.length; i++) {
      final path = parts.take(i + 1).join('/');
      final separator = web.document.createElement('span')..textContent = '/';
      separator.setAttribute('aria-hidden', 'true');
      breadcrumbs.appendChild(separator);
      final button = _action(parts[i], () => _navigate(path));
      if (i == parts.length - 1) {
        button.setAttribute('aria-current', 'location');
      }
      breadcrumbs.appendChild(button);
    }
    _button('folder-up').disabled = _path.isEmpty;
  }

  web.HTMLTableCellElement _cell(
    web.HTMLTableRowElement row,
    String text, [
    String className = '',
  ]) {
    final cell = web.document.createElement('td') as web.HTMLTableCellElement;
    cell.textContent = text;
    cell.className = className;
    row.appendChild(cell);
    return cell;
  }

  void _renderRows() {
    final tbody = web.document.getElementById('file-rows')!;
    tbody.textContent = '';
    _rows.clear();
    _checkboxes.clear();
    final visible = _visible;
    for (final entry in visible) {
      final row = web.document.createElement('tr') as web.HTMLTableRowElement;
      row.setAttribute('data-path', entry.path);
      final checkbox =
          web.document.createElement('input') as web.HTMLInputElement;
      checkbox.type = 'checkbox';
      checkbox.setAttribute('aria-label', 'Select ${entry.name}');
      checkbox.onChange.listen((_) {
        if (checkbox.checked) {
          _selected.add(entry.path);
        } else {
          _selected.remove(entry.path);
        }
        _updateSelection();
      });
      _cell(row, '', 'file-check').appendChild(checkbox);
      final nameCell = _cell(row, '', 'file-name');
      final name = _action(entry.name, () {
        if (entry.isDirectory) {
          _navigate(entry.path);
        } else {
          if (!_selected.add(entry.path)) _selected.remove(entry.path);
          _updateSelection();
        }
      }, className: 'file-name-button');
      name.title = entry.isDirectory
          ? 'Open ${entry.name}'
          : 'Select ${entry.name}';
      final icon = web.document.createElement('span')
        ..className = 'file-type-icon';
      icon.setAttribute('aria-hidden', 'true');
      icon.innerHTML =
          (entry.isDirectory
                  ? '<svg viewBox="0 0 24 24"><path d="M3 6h7l2 2h9v12H3z"/></svg>'
                  : '<svg viewBox="0 0 24 24"><path d="M6 3h8l4 4v14H6zM14 3v5h4"/></svg>')
              .toJS;
      name.insertBefore(icon, name.firstChild);
      nameCell.appendChild(name);
      _cell(row, entry.isDirectory ? 'Folder' : 'File', 'file-kind');
      _cell(row, entry.isDirectory ? '—' : _size(entry.sizeBytes), 'file-size');
      _cell(row, _date(entry.modified), 'file-modified');
      final actions = _cell(row, '', 'file-row-actions');
      final downloadButton = _action(
        entry.isDirectory ? 'Download ZIP' : 'Download',
        () => _downloadEntry(entry),
      );
      downloadButton.setAttribute(
        'aria-label',
        entry.isDirectory
            ? 'Download ${entry.name} as ZIP'
            : 'Download ${entry.name}',
      );
      actions.appendChild(downloadButton);
      if (entry.isDirectory && _path.isEmpty) {
        final saveButton = _action(
          'Save actions',
          () => onSaveActions(entry.name),
        );
        saveButton.setAttribute('aria-label', 'Save actions for ${entry.name}');
        actions.appendChild(saveButton);
      }
      tbody.appendChild(row);
      _rows[entry.path] = row;
      _checkboxes[entry.path] = checkbox;
    }
    final message =
        web.document.getElementById('file-list-message')! as web.HTMLElement;
    message.hidden = visible.isNotEmpty.toJS;
    message.textContent = _entries.isEmpty
        ? 'This folder is empty.'
        : 'No matching files or folders.';
    web.document.getElementById('file-item-count')!.textContent =
        '${visible.length} of ${_entries.length} items';
    _updateSelection();
  }

  void _updateSelection() {
    for (final entry in _checkboxes.entries) {
      final selected = _selected.contains(entry.key);
      entry.value.checked = selected;
      _rows[entry.key]!.classList.toggle('selected', selected);
    }
    _selectAll.checked =
        _selected.isNotEmpty && _selected.length == _visible.length;
    _selectAll.indeterminate = _selected.isNotEmpty && !_selectAll.checked;
    _selectAll.disabled = _visible.isEmpty;
    _button('download-selection').disabled = _selected.isEmpty;
    _button('clear-file-selection').disabled = _selected.isEmpty;
    web.document.getElementById('file-selection-count')!.textContent =
        '${_selected.length} selected';
  }

  void _downloadEntry(CardEntry entry) {
    try {
      if (entry.isDirectory) {
        download(
          '${entry.name}.zip',
          CardImage.exportContentsZip(card(), paths: [entry.path]),
          true,
        );
      } else {
        download(entry.name, CardImage.readFile(card(), entry.path), false);
      }
    } catch (e) {
      onError('Could not download ${entry.name}: $e');
    }
  }

  void _downloadSelection() {
    if (_selected.isEmpty) return;
    try {
      download(
        CardImage.downloadName(cardName(), 'selected.zip'),
        CardImage.exportContentsZip(card(), paths: _selected),
        true,
      );
    } catch (e) {
      onError('Could not export selection: $e');
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _date(DateTime date) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  }
}
