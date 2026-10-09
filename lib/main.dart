import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';


part 'models/fatura_models.dart';
part 'parsers/parser_itau.dart';
part 'screens/home_page.dart';

void main() => runApp(const ConferidorApp());
