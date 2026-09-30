import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const ConferidorApp());
}

// ============================================================
// MODELOS
// ============================================================

class Lancamento {
  final String data;
  final String descricao;
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacoes;

  Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    this.parcelaAtual,
    this.totalParcelas,
    this.observacoes = '',
  });

  bool get parcelada =>
      parcelaAtual != null && totalParcelas != null;
}

class ResultadoFatura {
  final double? totalFatura;
  final double? totalCartaoInformado;
  final double? totalInternacionalInformado;
  final double? totalServicosInformado;
  final List<Lancamento> lancamentos;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
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
    return lancamentos.where((e) => e.parcelada).length;
  }

  bool get conciliada {
    if (diferenca == null) return false;
    return diferenca!.abs() < 0.01;
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;

  FaturaProcessada({
    required this.arquivo,
    required this.resultado,
  });
}

// ============================================================
// PARSER ITAÚ
// ============================================================

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

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? procurarValor(
    String texto,
    RegExp expressao,
  ) {
    final match = expressao.firstMatch(texto);

    if (match == null || match.group(1) == null) {
      return null;
    }

    return moedaParaDouble(match.group(1)!);
  }

  static String normalizarCategoria(String categoria) {
    final c = categoria.trim().toLowerCase();

    switch (c) {
      case 'vestuario':
        return 'vestuário';
      case 'saude':
        return 'saúde';
      case 'servicos':
        return 'serviços';
      case 'eletronicos':
        return 'eletrônicos';
      case 'supermarket':
        return 'supermercado';
      case 'health':
        return 'saúde';
      case 'money':
        return 'serviços';
      case 'hotel':
        return 'hotel';
      default:
        return c;
    }
  }

  // ==========================================================
  // COMPRAS
  // ==========================================================

  static List<Lancamento> lerCompras(String texto) {
    final resultado = <Lancamento>[];

    final inicio =
        texto.indexOf('Lançamentos: compras e saques');

    final fim =
        texto.indexOf('Lançamentos no cartão');

    if (inicio < 0 || fim <= inicio) {
      return resultado;
    }

    var secao = texto.substring(inicio, fim);

    secao = secao.replaceAll(
      RegExp(
        r'Lançamentos:\s*compras\s*e\s*saques',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll(
      RegExp(
        r'DATAESTABELECIMENTOVALOR\s*EM\s*R\$',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll('continua...', '');

    secao = secao
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    final categorias =
        r'(restaurante|supermercado|vestuário|vestuario|'
        r'saúde|saude|serviços|servicos|outros|lazer|'
        r'eletronicos|eletrônicos|hotel|health|money|'
        r'supermarket)';

    final regexLancamento = RegExp(
      r'(\d{2}/\d{2})'
      r'(.+?)'
      r'(?:\s(\d{2})/(\d{2}))?'
      r'(-?[\d\.]+,\d{2})'
      + categorias,
      caseSensitive: false,
    );

    final matches = regexLancamento.allMatches(secao);

    for (final match in matches) {
      final data = match.group(1) ?? '';

      var descricao = match.group(2) ?? '';

      final parcelaAtual =
          int.tryParse(match.group(3) ?? '');

      final totalParcelas =
          int.tryParse(match.group(4) ?? '');

      final valorTexto = match.group(5);
      final categoriaTexto = match.group(6);

      if (valorTexto == null || categoriaTexto == null) {
        continue;
      }

      descricao = limparEspacos(descricao);

      int? parcelaFinal = parcelaAtual;
      int? totalParcelasFinal = totalParcelas;

      final parcelaNaDescricao = RegExp(
        r'\s(\d{2})/(\d{2})$',
      ).firstMatch(descricao);

      if (parcelaNaDescricao != null) {
        parcelaFinal =
            int.tryParse(parcelaNaDescricao.group(1)!);

        totalParcelasFinal =
            int.tryParse(parcelaNaDescricao.group(2)!);

        descricao = descricao
            .substring(0, parcelaNaDescricao.start)
            .trim();
      }

      if (descricao.isEmpty) continue;

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria:
              normalizarCategoria(categoriaTexto),
          valor: moedaParaDouble(valorTexto),
          parcelaAtual: parcelaFinal,
          totalParcelas: totalParcelasFinal,
          tipo: parcelaFinal != null &&
                  totalParcelasFinal != null
              ? 'Parcelada'
              : 'À vista',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // INTERNACIONAL
  // ==========================================================

  static List<Lancamento> lerInternacional(String texto) {
    final resultado = <Lancamento>[];

    final inicio =
        texto.indexOf('Lançamentos internacionais');

    final fim =
        texto.indexOf('Lançamentos: produtos e serviços');

    if (inicio < 0 || fim <= inicio) {
      return resultado;
    }

    final secao = texto.substring(inicio, fim);

    final totalCompra = procurarValor(
      secao,
      RegExp(
        r'Total transações inter\.\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final iof = procurarValor(
      secao,
      RegExp(
        r'Repasse de IOF\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    String data = '';
    String descricao = 'Compra internacional';

    final dataMatch =
        RegExp(r'(\d{2}/\d{2})').firstMatch(secao);

    if (dataMatch != null) {
      data = dataMatch.group(1) ?? '';
    }

    final descricaoMatch = RegExp(
      r'\d{2}/\d{2}'
      r'(.+?)'
      r'[\d\.]+,\d{2}'
      r'[\d\.]+,\d{2}'
      r'BRL',
      caseSensitive: false,
    ).firstMatch(secao);

    if (descricaoMatch != null) {
      var encontrada =
          limparEspacos(descricaoMatch.group(1) ?? '');

      if (encontrada.endsWith('S')) {
        encontrada =
            encontrada.substring(0, encontrada.length - 1);
      }

      if (encontrada.trim().isNotEmpty) {
        descricao = encontrada.trim();
      }
    }

    if (totalCompra != null) {
      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: 'internacional',
          valor: totalCompra,
          tipo: 'Internacional',
          observacoes: 'Transação internacional',
        ),
      );
    }

    if (iof != null) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'Repasse de IOF - transação internacional',
          categoria: 'encargos',
          valor: iof,
          tipo: 'Encargo / IOF',
          observacoes:
              'IOF da transação internacional',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PRODUTOS E SERVIÇOS
  // ==========================================================

  static List<Lancamento> lerProdutosServicos(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final inicio =
        texto.indexOf('Lançamentos: produtos e serviços');

    final fim =
        texto.indexOf('Total dos lançamentos atuais');

    if (inicio < 0 || fim <= inicio) {
      return resultado;
    }

    var secao = texto.substring(inicio, fim);

    secao = secao.replaceAll(
      RegExp(
        r'Lançamentos:\s*produtos\s*e\s*serviços',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao.replaceAll(
      RegExp(
        r'DATAPRODUTOS/SERVIÇOSVALOR\s*EM\s*R\$',
        caseSensitive: false,
      ),
      '',
    );

    secao = secao
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    final datas =
        RegExp(r'\d{2}/\d{2}').allMatches(secao).toList();

    for (int i = 0; i < datas.length; i++) {
      final atual = datas[i];

      final inicioBloco = atual.start;

      final fimBloco = i + 1 < datas.length
          ? datas[i + 1].start
          : secao.length;

      var bloco =
          secao.substring(inicioBloco, fimBloco);

      final data = bloco.substring(0, 5);

      bloco = bloco.substring(5);

      final valorMatch = RegExp(
        r'(-?[\d\.]+,\d{2})',
      ).firstMatch(bloco);

      if (valorMatch == null) continue;

      var descricao =
          bloco.substring(0, valorMatch.start);

      descricao = limparEspacos(descricao);

      if (descricao.isEmpty) {
        descricao = 'Produto/serviço Itaú';
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: 'produtos e serviços',
          valor: moedaParaDouble(
            valorMatch.group(1)!,
          ),
          tipo: 'Produto/Serviço',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PROCESSAMENTO
  // ==========================================================

  static ResultadoFatura processar(
    String textoOriginal,
  ) {
    final texto = textoOriginal
        .replaceAll('\r', '')
        .replaceAll('\n', '');

    final totalFatura = procurarValor(
      texto,
      RegExp(
        r'Total desta fatura([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalCartao = procurarValor(
      texto,
      RegExp(
        r'Lançamentos no cartão([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalInternacional = procurarValor(
      texto,
      RegExp(
        r'Total lançamentos\s*inter\.\s*em R\$'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final totalServicos = procurarValor(
      texto,
      RegExp(
        r'Lançamentos produtos e serviços'
        r'([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final lancamentos = <Lancamento>[];

    lancamentos.addAll(lerCompras(texto));
    lancamentos.addAll(lerInternacional(texto));
    lancamentos.addAll(lerProdutosServicos(texto));

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado: totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado: totalServicos,
      lancamentos: lancamentos,
    );
  }
}

// ============================================================
// APP
// ============================================================

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

// ============================================================
// TELA PRINCIPAL
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool processando = false;
  bool gerandoExcel = false;

  String status =
      'Selecione uma ou mais faturas Itaú em PDF.';

  final List<FaturaProcessada> faturas = [];

  int get quantidadeConciliadas => faturas
      .where((f) => f.resultado.conciliada)
      .length;

  int get quantidadeDivergentes =>
      faturas.length - quantidadeConciliadas;

  int get totalLancamentos => faturas.fold(
        0,
        (total, f) =>
            total + f.resultado.lancamentos.length,
      );

  int get totalParceladas => faturas.fold(
        0,
        (total, f) =>
            total + f.resultado.quantidadeParceladas,
      );

  double get valorTotalFaturas => faturas.fold(
        0.0,
        (total, f) =>
            total + (f.resultado.totalFatura ?? 0),
      );

  double get somaTotalLancamentos => faturas.fold(
        0.0,
        (total, f) => total + f.resultado.soma,
      );

  double get diferencaTotal =>
      valorTotalFaturas - somaTotalLancamentos;

  bool get todasConciliadas =>
      faturas.isNotEmpty &&
      faturas.every((f) => f.resultado.conciliada);

  // ==========================================================
  // SELECIONAR VÁRIOS PDFs
  // ==========================================================

  Future<void> selecionarFaturas() async {
    try {
      final escolha =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (escolha == null || escolha.files.isEmpty) {
        return;
      }

      setState(() {
        processando = true;
        faturas.clear();
        status =
            'Processando ${escolha.files.length} fatura(s)...';
      });

      for (int i = 0; i < escolha.files.length; i++) {
        final arquivo = escolha.files[i];

        if (arquivo.path == null) continue;

        setState(() {
          status =
              'Processando ${i + 1} de '
              '${escolha.files.length}:\n'
              '${arquivo.name}';
        });

        final bytes =
            await File(arquivo.path!).readAsBytes();

        final documento =
            PdfDocument(inputBytes: bytes);

        final texto =
            PdfTextExtractor(documento).extractText();

        documento.dispose();

        if (texto.trim().isEmpty) continue;

        final resultado =
            ParserItau.processar(texto);

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: resultado,
          ),
        );
      }

      setState(() {
        processando = false;

        if (faturas.isEmpty) {
          status =
              'Nenhuma fatura pôde ser processada.';
        } else if (todasConciliadas) {
          status =
              '${faturas.length} fatura(s) '
              'processada(s) e conferida(s).';
        } else {
          status =
              '${faturas.length} fatura(s) processada(s). '
              '$quantidadeDivergentes '
              'fatura(s) com divergência.';
        }
      });
    } catch (e) {
      setState(() {
        processando = false;
        status = 'Erro ao processar:\n$e';
      });
    }
  }

  // ==========================================================
  // GERAR EXCEL CONSOLIDADO
  // ==========================================================

  Future<void> gerarExcelConsolidado() async {
    if (faturas.isEmpty) return;

    if (!todasConciliadas) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todas as faturas precisam estar '
            'conciliadas antes da exportação.',
          ),
        ),
      );
      return;
    }

    try {
      setState(() {
        gerandoExcel = true;
      });

      final excel = Excel.createExcel();

      // ------------------------------------------------------
      // LANÇAMENTOS
      // ------------------------------------------------------

      final lancamentos = excel['Lançamentos'];

      lancamentos.appendRow([
        TextCellValue('Fatura / Arquivo'),
        TextCellValue('Data da compra'),
        TextCellValue('Descrição da compra'),
        TextCellValue('Categoria'),
        TextCellValue('Valor'),
        TextCellValue('Parcela atual'),
        TextCellValue('Total de parcelas'),
        TextCellValue('Tipo'),
        TextCellValue('Observações'),
      ]);

      for (final fatura in faturas) {
        for (final item
            in fatura.resultado.lancamentos) {
          lancamentos.appendRow([
            TextCellValue(fatura.arquivo),
            TextCellValue(item.data),
            TextCellValue(item.descricao),
            TextCellValue(item.categoria),
            DoubleCellValue(item.valor),
            item.parcelaAtual == null
                ? TextCellValue('')
                : IntCellValue(item.parcelaAtual!),
            item.totalParcelas == null
                ? TextCellValue('')
                : IntCellValue(item.totalParcelas!),
            TextCellValue(item.tipo),
            TextCellValue(item.observacoes),
          ]);
        }
      }

      lancamentos.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('TOTAL CONSOLIDADO'),
        TextCellValue(''),
        DoubleCellValue(somaTotalLancamentos),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      lancamentos.setColumnWidth(0, 35);
      lancamentos.setColumnWidth(1, 15);
      lancamentos.setColumnWidth(2, 40);
      lancamentos.setColumnWidth(3, 22);
      lancamentos.setColumnWidth(4, 16);
      lancamentos.setColumnWidth(5, 15);
      lancamentos.setColumnWidth(6, 20);
      lancamentos.setColumnWidth(7, 20);
      lancamentos.setColumnWidth(8, 35);

      // ------------------------------------------------------
      // CONFERÊNCIA
      // ------------------------------------------------------

      final conferencia = excel['Conferência'];

      conferencia.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Total da fatura'),
        TextCellValue('Soma dos lançamentos'),
        TextCellValue('Diferença'),
        TextCellValue('Lançamentos'),
        TextCellValue('Parceladas'),
        TextCellValue('Cartão Itaú'),
        TextCellValue('Internacional'),
        TextCellValue('Produtos/serviços'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r = fatura.resultado;

        conferencia.appendRow([
          TextCellValue(fatura.arquivo),
          DoubleCellValue(r.totalFatura ?? 0),
          DoubleCellValue(r.soma),
          DoubleCellValue(r.diferenca ?? 0),
          IntCellValue(r.lancamentos.length),
          IntCellValue(r.quantidadeParceladas),
          DoubleCellValue(
            r.totalCartaoInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalInternacionalInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalServicosInformado ?? 0,
          ),
          TextCellValue(
            r.conciliada
                ? 'CONCILIADA'
                : 'DIVERGENTE',
          ),
        ]);
      }

      conferencia.appendRow([
        TextCellValue('TOTAL CONSOLIDADO'),
        DoubleCellValue(valorTotalFaturas),
        DoubleCellValue(somaTotalLancamentos),
        DoubleCellValue(diferencaTotal),
        IntCellValue(totalLancamentos),
        IntCellValue(totalParceladas),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(
          todasConciliadas
              ? 'CONCILIADO'
              : 'DIVERGENTE',
        ),
      ]);

      conferencia.setColumnWidth(0, 35);
      conferencia.setColumnWidth(1, 20);
      conferencia.setColumnWidth(2, 22);
      conferencia.setColumnWidth(3, 18);
      conferencia.setColumnWidth(4, 16);
      conferencia.setColumnWidth(5, 16);
      conferencia.setColumnWidth(6, 18);
      conferencia.setColumnWidth(7, 18);
      conferencia.setColumnWidth(8, 22);
      conferencia.setColumnWidth(9, 18);

      // ------------------------------------------------------
      // DIVERGÊNCIAS
      // ------------------------------------------------------

      if (!todasConciliadas) {
        final divergencias = excel['Divergências'];

        divergencias.appendRow([
          TextCellValue('Arquivo'),
          TextCellValue('Total da fatura'),
          TextCellValue('Soma'),
          TextCellValue('Diferença'),
          TextCellValue('Observação'),
        ]);

        for (final fatura in faturas) {
          final r = fatura.resultado;

          if (!r.conciliada) {
            divergencias.appendRow([
              TextCellValue(fatura.arquivo),
              DoubleCellValue(r.totalFatura ?? 0),
              DoubleCellValue(r.soma),
              DoubleCellValue(r.diferenca ?? 0),
              TextCellValue(
                'Fatura requer revisão.',
              ),
            ]);
          }
        }

        divergencias.setColumnWidth(0, 35);
        divergencias.setColumnWidth(1, 20);
        divergencias.setColumnWidth(2, 20);
        divergencias.setColumnWidth(3, 20);
        divergencias.setColumnWidth(4, 35);
      }

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes = excel.encode();

      if (bytes == null) {
        throw Exception(
          'Não foi possível gerar o arquivo Excel.',
        );
      }

      final pasta = await getTemporaryDirectory();

      final agora = DateTime.now();

      final nome =
          'Faturas_Itau_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}'
          '_consolidado.xlsx';

      final arquivo =
          File('${pasta.path}/$nome');

      await arquivo.writeAsBytes(
        bytes,
        flush: true,
      );

      if (!mounted) return;

      setState(() {
        gerandoExcel = false;
      });

      await Share.shareXFiles(
        [
          XFile(
            arquivo.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: 'Faturas Itaú consolidadas',
        text:
            '${faturas.length} fatura(s) '
            'processada(s) e conferida(s).',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        gerandoExcel = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao gerar Excel: $e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // FORMATAÇÃO
  // ==========================================================

  String dinheiro(double valor) {
    final sinal = valor < 0 ? '-' : '';

    final partes =
        valor.abs().toStringAsFixed(2).split('.');

    final inteiro = partes[0];
    final buffer = StringBuffer();

    for (int i = 0; i < inteiro.length; i++) {
      final restante = inteiro.length - i;

      buffer.write(inteiro[i]);

      if (restante > 1 && restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${sinal}R\$ '
        '${buffer.toString()},${partes[1]}';
  }

  Widget linhaResumo(
    String titulo,
    String valor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo),
          ),
          const SizedBox(width: 8),
          Text(
            valor,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // INTERFACE
  // ==========================================================

  @override
  Widget build(BuildContext context) {
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
            size: 65,
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed:
                processando ? null : selecionarFaturas,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar faturas PDF',
            ),
          ),

          const SizedBox(height: 16),

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

          if (faturas.isNotEmpty) ...[
            const SizedBox(height: 20),

            const Text(
              'Resumo consolidado',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    linhaResumo(
                      'Faturas processadas',
                      '${faturas.length}',
                    ),
                    linhaResumo(
                      'Faturas conciliadas',
                      '$quantidadeConciliadas',
                    ),
                    linhaResumo(
                      'Faturas divergentes',
                      '$quantidadeDivergentes',
                    ),

                    const Divider(),

                    linhaResumo(
                      'Total das faturas',
                      dinheiro(valorTotalFaturas),
                    ),
                    linhaResumo(
                      'Soma dos lançamentos',
                      dinheiro(somaTotalLancamentos),
                    ),
                    linhaResumo(
                      'Diferença consolidada',
                      dinheiro(diferencaTotal),
                    ),
                    linhaResumo(
                      'Lançamentos',
                      '$totalLancamentos',
                    ),
                    linhaResumo(
                      'Compras parceladas',
                      '$totalParceladas',
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Icon(
                          todasConciliadas
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: todasConciliadas
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            todasConciliadas
                                ? 'Todas as faturas conciliadas'
                                : 'Existem faturas divergentes',
                            style: const TextStyle(
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

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: todasConciliadas &&
                      !gerandoExcel
                  ? gerarExcelConsolidado
                  : null,
              icon: gerandoExcel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.table_view,
                    ),
              label: Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : 'Gerar Excel consolidado',
              ),
            ),

            if (!todasConciliadas)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'A exportação fica bloqueada até '
                  'todas as faturas apresentarem '
                  'diferença de R\$ 0,00.',
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 26),

            const Text(
              'Conferência por fatura',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            ...faturas.map(
              (fatura) {
                final r = fatura.resultado;

                return Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          fatura.arquivo,
                          style: const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 10),

                        linhaResumo(
                          'Total da fatura',
                          dinheiro(
                            r.totalFatura ?? 0,
                          ),
                        ),

                        linhaResumo(
                          'Soma dos lançamentos',
                          dinheiro(r.soma),
                        ),

                        linhaResumo(
                          'Diferença',
                          dinheiro(
                            r.diferenca ?? 0,
                          ),
                        ),

                        linhaResumo(
                          'Lançamentos',
                          '${r.lancamentos.length}',
                        ),

                        linhaResumo(
                          'Parceladas',
                          '${r.quantidadeParceladas}',
                        ),

                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Icon(
                              r.conciliada
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color: r.conciliada
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              r.conciliada
                                  ? 'Conciliada'
                                  : 'Divergente',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
