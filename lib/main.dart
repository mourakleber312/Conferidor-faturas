import 'dart:io';

import 'package:flutter/material.dart';
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
      0,
      (anterior, item) => anterior + item.valor,
    );
  }

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  int get quantidadeParceladas =>
      lancamentos.where((item) => item.parcelada).length;
}

class ParserItau {
  static double moedaParaDouble(String valor) {
    var texto = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    if (texto.contains(',')) {
      texto = texto
          .replaceAll('.', '')
          .replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  static ResultadoFatura processar(String texto) {
    final lancamentos = <Lancamento>[];

    double? totalFatura;

    final expressoesTotal = [
      RegExp(
        r'total\s+(?:desta\s+)?fatura[^\d]{0,30}([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
      RegExp(
        r'valor\s+total[^\d]{0,30}([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
      RegExp(
        r'total\s+dos\s+lançamentos[^\d]{0,30}([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    ];

    for (final expressao in expressoesTotal) {
      final resultado = expressao.firstMatch(texto);

      if (resultado != null) {
        totalFatura =
            moedaParaDouble(resultado.group(1)!);
        break;
      }
    }

    final linhas = texto
        .replaceAll('\r', '\n')
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();

    final regexLinha = RegExp(
      r'^(\d{2}/\d{2})(?:/\d{2,4})?\s+(.+?)\s+'
      r'(?:(\d{1,2})/(\d{1,2})\s+)?'
      r'(-?[\d\.]+,\d{2})$',
    );

    for (final linha in linhas) {
      final match = regexLinha.firstMatch(linha);

      if (match == null) continue;

      final data = match.group(1)!;
      final descricao = match.group(2)!.trim();

      final parcelaAtual =
          int.tryParse(match.group(3) ?? '');

      final totalParcelas =
          int.tryParse(match.group(4) ?? '');

      final valor =
          moedaParaDouble(match.group(5)!);

      // Evita capturar algumas linhas de resumo.
      final descricaoMinuscula =
          descricao.toLowerCase();

      if (descricaoMinuscula.contains(
            'total da fatura',
          ) ||
          descricaoMinuscula.contains(
            'pagamento mínimo',
          )) {
        continue;
      }

      lancamentos.add(
        Lancamento(
          data: data,
          descricao: descricao,
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
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
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool processando = false;

  String status =
      'Selecione uma fatura Itaú em PDF.';

  String? nomeArquivo;

  ResultadoFatura? resultado;

  Future<void> selecionarFatura() async {
    try {
      setState(() {
        processando = true;
        status = 'Abrindo fatura...';
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

      nomeArquivo = arquivo.name;

      setState(() {
        status = 'Extraindo texto do PDF...';
      });

      final bytes =
          await File(arquivo.path!).readAsBytes();

      final documento =
          PdfDocument(inputBytes: bytes);

      final texto =
          PdfTextExtractor(documento).extractText();

      documento.dispose();

      if (texto.trim().isEmpty) {
        throw Exception(
          'O PDF não possui texto pesquisável. '
          'Será necessário OCR.',
        );
      }

      setState(() {
        status = 'Analisando lançamentos...';
      });

      final analise =
          ParserItau.processar(texto);

      setState(() {
        resultado = analise;
        processando = false;

        if (analise.lancamentos.isEmpty) {
          status =
              'PDF lido, mas nenhum lançamento '
              'foi reconhecido automaticamente.';
        } else {
          status =
              'Análise concluída.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;
        status = 'Erro:\n$e';
      });
    }
  }

  String dinheiro(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
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
            onPressed:
                processando ? null : selecionarFatura,
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
              child: CircularProgressIndicator(),
            ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(status),
            ),
          ),

          if (nomeArquivo != null)
            Padding(
              padding:
                  const EdgeInsets.only(top: 8),
              child: Text(
                'Arquivo: $nomeArquivo',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

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
                          ? 'Total da fatura: não identificado'
                          : 'Total da fatura: ${dinheiro(r.totalFatura!)}',
                    ),

                    Text(
                      'Soma dos lançamentos: '
                      '${dinheiro(r.soma)}',
                    ),

                    Text(
                      r.diferenca == null
                          ? 'Diferença: não calculada'
                          : 'Diferença: ${dinheiro(r.diferenca!)}',
                    ),

                    Text(
                      'Lançamentos encontrados: '
                      '${r.lancamentos.length}',
                    ),

                    Text(
                      'Compras parceladas: '
                      '${r.quantidadeParceladas}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Lançamentos encontrados',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            ...r.lancamentos.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.descricao),

                  subtitle: Text(
                    item.parcelada
                        ? '${item.data} • '
                          '${item.parcelaAtual}/'
                          '${item.totalParcelas}'
                        : '${item.data} • À vista',
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
      ),
    );
  }
}
