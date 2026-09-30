import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const ConferidorApp());
}

class ConferidorApp extends StatelessWidget {
  const ConferidorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Conferidor de Faturas',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String status = 'Nenhuma fatura selecionada.';
  String? nomeArquivo;
  String? textoExtraido;
  bool processando = false;

  Future<void> selecionarFatura() async {
    try {
      setState(() {
        processando = true;
        status = 'Selecionando fatura...';
      });

      final resultado = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (resultado == null) {
        setState(() {
          processando = false;
          status = 'Seleção cancelada.';
        });
        return;
      }

      final arquivo = resultado.files.single;

      if (arquivo.path == null) {
        throw Exception('Não foi possível acessar o PDF.');
      }

      setState(() {
        nomeArquivo = arquivo.name;
        status = 'Lendo PDF...';
      });

      final bytes = await File(arquivo.path!).readAsBytes();

      final documento = PdfDocument(inputBytes: bytes);

      final texto = PdfTextExtractor(
        documento,
      ).extractText();

      documento.dispose();

      setState(() {
        textoExtraido = texto;
        processando = false;

        if (texto.trim().isEmpty) {
          status =
              'PDF aberto, mas nenhum texto foi encontrado. '
              'Essa fatura poderá precisar de leitura visual/OCR.';
        } else {
          status = 'Fatura lida com sucesso.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;
        status = 'Erro ao processar a fatura:\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferidor de Faturas'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Icon(
              Icons.credit_card,
              size: 72,
            ),

            const SizedBox(height: 20),

            Text(
              'Conferidor de Faturas',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),

            const SizedBox(height: 30),

            FilledButton.icon(
              onPressed: processando ? null : selecionarFatura,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Selecionar fatura PDF'),
            ),

            const SizedBox(height: 24),

            if (processando)
              const Center(
                child: CircularProgressIndicator(),
              ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(status),
              ),
            ),

            if (nomeArquivo != null) ...[
              const SizedBox(height: 12),
              Text(
                'Arquivo: $nomeArquivo',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            if (textoExtraido != null &&
                textoExtraido!.trim().isNotEmpty) ...[
              const SizedBox(height: 24),

              const Text(
                'Prévia da leitura:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  textoExtraido!.length > 3000
                      ? textoExtraido!.substring(0, 3000)
                      : textoExtraido!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
