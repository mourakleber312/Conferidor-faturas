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
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacao;

  Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    required this.observacao,
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

  double get soma => lancamentos.fold(
        0.0,
        (total, item) => total + item.valor,
      );

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  int get quantidadeParceladas =>
      lancamentos.where((e) => e.parcelada).length;

  bool get conciliada =>
      diferenca != null && diferenca!.abs() < 0.01;
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

    final numero = double.tryParse(texto) ?? 0.0;

    return negativo ? -numero : numero;
  }

  static String normalizar(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static bool linhaIgnorada(String linha) {
    final l = linha.toLowerCase();

    final termos = [
      'total da fatura',
      'pagamento mínimo',
      'pagamento minimo',
      'limite de crédito',
      'limite de credito',
      'melhor data',
      'vencimento',
      'saldo anterior',
      'total de pagamentos',
      'total dos lançamentos',
      'total dos lancamentos',
      'compras parceladas - próximas faturas',
      'compras parceladas - proximas faturas',
      'próximas faturas',
      'proximas faturas',
    ];

    return termos.any(l.contains);
  }

  static bool pareceComplemento(String linha) {
    if (linha.isEmpty) return false;

    if (RegExp(r'^\d{2}/\d{2}').hasMatch(linha)) {
      return false;
    }

    if (RegExp(r'^[\d\.,\-]+\s*$').hasMatch(linha)) {
      return false;
    }

    return true;
  }

  static String categoriaDaLinha(String linha) {
    final l = linha.toLowerCase();

    const categorias = [
      'alimentação',
      'alimentacao',
      'restaurante',
      'supermercado',
      'vestuário',
      'vestuario',
      'saúde',
      'saude',
      'transporte',
      'serviços',
      'servicos',
      'educação',
      'educacao',
      'lazer',
      'viagem',
      'casa',
      'outros',
    ];

    for (final categoria in categorias) {
      if (l.contains(categoria)) {
        return categoria;
      }
    }

    return '';
  }

  static ResultadoFatura processar(String texto) {
    final lancamentos = <Lancamento>[];

    double? totalFatura;

    // ----------------------------
    // TOTAL DA FATURA
    // ----------------------------

    final expressoesTotal = [
      RegExp(
        r'total\s+(?:desta\s+)?fatura[^\d]{0,50}'
        r'(?:R\$\s*)?([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
      RegExp(
        r'valor\s+total[^\d]{0,50}'
        r'(?:R\$\s*)?([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    ];

    for (final expressao in expressoesTotal) {
      final match = expressao.firstMatch(texto);

      if (match != null) {
        totalFatura = moedaParaDouble(match.group(1)!);
        break;
      }
    }

    // ----------------------------
    // PREPARAÇÃO DAS LINHAS
    // ----------------------------

    final linhas = texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(normalizar)
        .where((linha) => linha.isNotEmpty)
        .toList();

    /*
      Exemplos que queremos reconhecer:

      25/04 JIM.COM* RIZZO 05/12 416,58

      03/08 AMAZON BRSAO PAULOBRA 52,28

      Também aceita ano:
      03/08/2026 EMPRESA XYZ 100,00
    */

    final regexCompra = RegExp(
      r'^(\d{2}/\d{2})(?:/\d{2,4})?\s+'
      r'(.+?)'
      r'(?:\s+(\d{1,2})/(\d{1,2}))?'
      r'\s+(-?[\d\.]+,\d{2})\s*$',
      caseSensitive: false,
    );

    // Evita processar a seção de parcelas futuras.
    bool ignorarParcelasFuturas = false;

    for (int i = 0; i < linhas.length; i++) {
      final linha = linhas[i];

      final minuscula = linha.toLowerCase();

      if (minuscula.contains('compras parceladas') &&
          (minuscula.contains('próximas') ||
              minuscula.contains('proximas'))) {
        ignorarParcelasFuturas = true;
        continue;
      }

      /*
        Se depois da seção de parcelas futuras aparecer
        uma nova seção relevante, podemos voltar a analisar.
      */
      if (ignorarParcelasFuturas &&
          (minuscula.contains('encargos') ||
              minuscula.contains('produtos e serviços') ||
              minuscula.contains('produtos e servicos') ||
              minuscula.contains('transações internacionais') ||
              minuscula.contains('transacoes internacionais'))) {
        ignorarParcelasFuturas = false;
      }

      if (ignorarParcelasFuturas) {
        continue;
      }

      if (linhaIgnorada(linha)) {
        continue;
      }

      final match = regexCompra.firstMatch(linha);

      if (match == null) {
        continue;
      }

      final data = match.group(1)!;

      String descricao =
          normalizar(match.group(2) ?? '');

      final parcelaAtual =
          int.tryParse(match.group(3) ?? '');

      final totalParcelas =
          int.tryParse(match.group(4) ?? '');

      final valor =
          moedaParaDouble(match.group(5)!);

      String categoria = '';
      String observacao = '';

      // --------------------------------
      // SEGUNDA LINHA DA COMPRA
      // --------------------------------

      if (i + 1 < linhas.length) {
        final proxima = linhas[i + 1];

        if (pareceComplemento(proxima) &&
            !linhaIgnorada(proxima)) {
          categoria = categoriaDaLinha(proxima);

          observacao = proxima;

          /*
            Não juntamos o complemento à descrição
            principal porque queremos preservá-lo
            separadamente para o futuro Excel.
          */
        }
      }

      String tipo = 'À vista';

      if (parcelaAtual != null &&
          totalParcelas != null) {
        tipo = 'Parcelada';
      }

      final descricaoLower =
          descricao.toLowerCase();

      if (descricaoLower.contains('iof')) {
        tipo = 'Encargo / IOF';
      }

      if (descricaoLower.contains('juros') ||
          descricaoLower.contains('multa') ||
          descricaoLower.contains('tarifa')) {
        tipo = 'Encargo';
      }

      lancamentos.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: categoria,
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: tipo,
          observacao: observacao,
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
              'foi reconhecido.';
        } else if (analise.conciliada) {
          status =
              'Fatura processada e conferida. '
              'Os lançamentos estão conciliados.';
        } else {
          status =
              'Fatura processada, mas ainda existe '
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

  String dinheiro(double valor) {
    final sinal = valor < 0 ? '-' : '';

    final absoluto = valor.abs();

    final partes =
        absoluto.toStringAsFixed(2).split('.');

    String inteiro = partes[0];

    final buffer = StringBuffer();

    for (int i = 0; i < inteiro.length; i++) {
      final restante = inteiro.length - i;

      buffer.write(inteiro[i]);

      if (restante > 1 &&
          restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${sinal}R\$ ${buffer.toString()},${partes[1]}';
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

          const SizedBox(height: 8),

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
                          ? 'Diferença: não calculada'
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
                          Expanded(
                            child: Text(
                              'Fatura conciliada',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
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
                          Expanded(
                            child: Text(
                              'Conferência pendente',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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
              (item) {
                String detalhe =
                    '${item.data} • ${item.tipo}';

                if (item.parcelada) {
                  detalhe +=
                      ' • ${item.parcelaAtual}'
                      '/${item.totalParcelas}';
                }

                if (item.categoria.isNotEmpty) {
                  detalhe +=
                      '\nCategoria: '
                      '${item.categoria}';
                }

                if (item.observacao.isNotEmpty) {
                  detalhe +=
                      '\n${item.observacao}';
                }

                return Card(
                  child: ListTile(
                    title: Text(
                      item.descricao,
                    ),
                    subtitle: Text(detalhe),
                    trailing: Text(
                      dinheiro(item.valor),
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
