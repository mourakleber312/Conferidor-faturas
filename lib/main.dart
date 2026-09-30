import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const ConferidorApp());
}

class Lancamento {
  final String data;
  final String descricao;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;

  Lancamento({
    required this.data,
    required this.descricao,
    required this.valor,
    this.parcelaAtual,
    this.totalParcelas,
  });

  bool get parcelada =>
      parcelaAtual != null && totalParcelas != null;
}

class ResultadoFatura {
  final double? totalFatura;
  final List<Lancamento> lancamentos;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
  });

  double get soma {
    return lancamentos.fold(
      0.0,
      (total, item) => total + item.valor,
    );
  }

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  int get quantidadeParceladas {
    return lancamentos
        .where((item) => item.parcelada)
        .length;
  }

  bool get conciliada {
    return diferenca != null &&
        diferenca!.abs() < 0.01;
  }
}

class ParserItau {
  static double moedaParaDouble(String valor) {
    var texto = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    bool negativo = false;

    if (texto.startsWith('-')) {
      negativo = true;
      texto = texto.substring(1);
    }

    texto = texto
        .replaceAll('.', '')
        .replaceAll(',', '.');

    final numero =
        double.tryParse(texto) ?? 0.0;

    return negativo ? -numero : numero;
  }

  static String normalizar(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static ResultadoFatura processar(
    String texto,
  ) {
    final lancamentos = <Lancamento>[];

    double? totalFatura;

    // Procura o total da fatura.
    final expressoesTotal = [
      RegExp(
        r'total\s+(?:desta\s+)?fatura'
        r'[^\d]{0,50}'
        r'(?:R\$\s*)?'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
      RegExp(
        r'valor\s+total'
        r'[^\d]{0,50}'
        r'(?:R\$\s*)?'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    ];

    for (final expressao in expressoesTotal) {
      final match =
          expressao.firstMatch(texto);

      if (match != null) {
        totalFatura = moedaParaDouble(
          match.group(1)!,
        );
        break;
      }
    }

    // Parser provisório.
    // Depois do diagnóstico vamos substituir
    // esta parte pelo padrão real da fatura.
    final linhas = texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(normalizar)
        .where((linha) => linha.isNotEmpty)
        .toList();

    final regexCompra = RegExp(
      r'^(\d{2}/\d{2})'
      r'(?:/\d{2,4})?'
      r'\s+(.+?)'
      r'(?:\s+(\d{1,2})/(\d{1,2}))?'
      r'\s+(-?[\d\.]+,\d{2})'
      r'\s*$',
    );

    for (final linha in linhas) {
      final match =
          regexCompra.firstMatch(linha);

      if (match == null) continue;

      final descricao =
          (match.group(2) ?? '').trim();

      final descricaoLower =
          descricao.toLowerCase();

      // Evita alguns resumos.
      if (descricaoLower.contains(
            'total da fatura',
          ) ||
          descricaoLower.contains(
            'pagamento mínimo',
          ) ||
          descricaoLower.contains(
            'pagamento minimo',
          )) {
        continue;
      }

      lancamentos.add(
        Lancamento(
          data: match.group(1)!,
          descricao: descricao,
          parcelaAtual: int.tryParse(
            match.group(3) ?? '',
          ),
          totalParcelas: int.tryParse(
            match.group(4) ?? '',
          ),
          valor: moedaParaDouble(
            match.group(5)!,
          ),
        ),
      );
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      lancamentos: lancamentos,
    );
  }
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
  State<HomePage> createState() {
    return _HomePageState();
  }
}

class _HomePageState extends State<HomePage> {
  bool processando = false;

  String status =
      'Selecione uma fatura Itaú em PDF.';

  String? nomeArquivo;

  String textoExtraido = '';

  ResultadoFatura? resultado;

  Future<void> selecionarFatura() async {
    try {
      setState(() {
        processando = true;
        status = 'Abrindo fatura...';
        nomeArquivo = null;
        textoExtraido = '';
        resultado = null;
      });

      final escolha =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (escolha == null) {
        setState(() {
          processando = false;
          status = 'Seleção cancelada.';
        });
        return;
      }

      final arquivo = escolha.files.single;

      if (arquivo.path == null) {
        throw Exception(
          'Não foi possível acessar o arquivo.',
        );
      }

      setState(() {
        nomeArquivo = arquivo.name;
        status = 'Extraindo texto do PDF...';
      });

      final bytes =
          await File(arquivo.path!)
              .readAsBytes();

      final documento = PdfDocument(
        inputBytes: bytes,
      );

      final texto = PdfTextExtractor(
        documento,
      ).extractText();

      documento.dispose();

      if (texto.trim().isEmpty) {
        throw Exception(
          'O PDF não possui texto pesquisável. '
          'Será necessário OCR.',
        );
      }

      final analise =
          ParserItau.processar(texto);

      setState(() {
        textoExtraido = texto;
        resultado = analise;
        processando = false;

        if (analise.lancamentos.isEmpty) {
          status =
              'PDF lido. Use "Copiar diagnóstico" '
              'para analisarmos o formato dos '
              'lançamentos.';
        } else if (analise.conciliada) {
          status =
              'Fatura processada e conferida.';
        } else {
          status =
              'Fatura processada, mas existe '
              'diferença na conferência.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;
        status = 'Erro:\n$e';
      });
    }
  }

  Future<void> copiarDiagnostico() async {
    if (textoExtraido.isEmpty) return;

    await Clipboard.setData(
      ClipboardData(
        text: textoExtraido,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Diagnóstico copiado. '
          'Agora cole o texto no ChatGPT.',
        ),
      ),
    );
  }

  String dinheiro(double valor) {
    final sinal =
        valor < 0 ? '-' : '';

    final absoluto = valor.abs();

    final partes =
        absoluto.toStringAsFixed(2).split('.');

    final inteiro = partes[0];

    final buffer = StringBuffer();

    for (int i = 0;
        i < inteiro.length;
        i++) {
      final restante =
          inteiro.length - i;

      buffer.write(inteiro[i]);

      if (restante > 1 &&
          restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${sinal}R\$ '
        '${buffer.toString()},'
        '${partes[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final r = resultado;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Conferidor de Faturas',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.credit_card,
            size: 70,
          ),

          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: processando
                ? null
                : selecionarFatura,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar fatura PDF',
            ),
          ),

          const SizedBox(height: 20),

          if (processando)
            const Center(
              child:
                  CircularProgressIndicator(),
            ),

          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Text(status),
            ),
          ),

          if (nomeArquivo != null) ...[
            const SizedBox(height: 8),

            Text(
              'Arquivo: $nomeArquivo',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          // BOTÃO DE DIAGNÓSTICO
          if (textoExtraido.isNotEmpty) ...[
            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: copiarDiagnostico,
              icon: const Icon(
                Icons.content_copy,
              ),
              label: const Text(
                'Copiar diagnóstico',
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Toque no botão acima e depois '
              'cole o conteúdo no ChatGPT.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
              ),
            ),
          ],

          if (r != null) ...[
            const SizedBox(height: 24),

            const Text(
              'Conferência',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.totalFatura == null
                          ? 'Total da fatura: '
                              'não identificado'
                          : 'Total da fatura: '
                              '${dinheiro(r.totalFatura!)}',
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Soma dos lançamentos: '
                      '${dinheiro(r.soma)}',
                    ),

                    const SizedBox(height: 5),

                    Text(
                      r.diferenca == null
                          ? 'Diferença: '
                              'não calculada'
                          : 'Diferença: '
                              '${dinheiro(r.diferenca!)}',
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Lançamentos encontrados: '
                      '${r.lancamentos.length}',
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'Compras parceladas: '
                      '${r.quantidadeParceladas}',
                    ),

                    const SizedBox(height: 12),

                    if (r.conciliada)
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Fatura conciliada',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Conferência pendente',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            if (r.lancamentos.isNotEmpty)
              ...[
                const SizedBox(height: 20),

                const Text(
                  'Lançamentos encontrados',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                ...r.lancamentos.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                        item.descricao,
                      ),
                      subtitle: Text(
                        item.parcelada
                            ? '${item.data} • '
                                '${item.parcelaAtual}/'
                                '${item.totalParcelas}'
                            : '${item.data} • '
                                'À vista',
                      ),
                      trailing: Text(
                        dinheiro(item.valor),
                        style: const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
