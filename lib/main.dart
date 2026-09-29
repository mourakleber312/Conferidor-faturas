import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

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
  String? arquivoSelecionado;

  Future<void> selecionarFatura() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (resultado != null) {
      setState(() {
        arquivoSelecionado = resultado.files.single.name;
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.credit_card,
              size: 80,
            ),
            const SizedBox(height: 24),

            Text(
              'Conferidor de Faturas',
              style: Theme.of(context).textTheme.headlineSmall,
            ),

            const SizedBox(height: 12),

            const Text(
              'Importe sua fatura de cartão em PDF para iniciar a conferência.',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: selecionarFatura,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Selecionar fatura PDF'),
            ),

            const SizedBox(height: 24),

            if (arquivoSelecionado != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Arquivo selecionado:\n$arquivoSelecionado',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
