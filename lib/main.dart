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

  final String vencimento;
  final String cartao;

  final List<Lancamento> lancamentos;
  final List<Lancamento> compras;
  final List<String> alertas;

  ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    required this.compras,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
    this.vencimento = '',
    this.cartao = '',
    this.alertas = const [],
  });

  double get soma => lancamentos.fold(
        0.0,
        (s, e) => s + e.valor,
      );

  double get somaCompras => compras.fold(
        0.0,
        (s, e) => s + e.valor,
      );

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  double? get diferencaCartao {
    if (totalCartaoInformado == null) return null;
    return totalCartaoInformado! - somaCompras;
  }

  int get quantidadeParceladas =>
      compras.where((e) => e.parcelada).length;

  bool get comprasReconstruidas {
    if (compras.isEmpty) return false;

    if (totalCartaoInformado != null) {
      return (totalCartaoInformado! - somaCompras).abs() < 0.02;
    }

    return true;
  }

  bool get totalConciliado {
    if (totalFatura == null || diferenca == null) return false;
    return diferenca!.abs() < 0.02;
  }

  bool get conciliada =>
      totalConciliado && comprasReconstruidas;

  bool get falhaLeitura =>
      totalFatura == null && compras.isEmpty;

  String get status {
    if (falhaLeitura) return 'FALHA DE LEITURA';

    if (conciliada) return 'CONCILIADA';

    if (totalConciliado && !comprasReconstruidas) {
      return 'INCOMPLETA';
    }

    return 'DIVERGENTE';
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
// PARSER
// ============================================================

class ParserItau {
  static String semAcentos(String texto) {
    return texto
        .replaceAll(RegExp('[áàãâäÁÀÃÂÄ]'), 'a')
        .replaceAll(RegExp('[éèêëÉÈÊË]'), 'e')
        .replaceAll(RegExp('[íìîïÍÌÎÏ]'), 'i')
        .replaceAll(RegExp('[óòõôöÓÒÕÔÖ]'), 'o')
        .replaceAll(RegExp('[úùûüÚÙÛÜ]'), 'u')
        .replaceAll(RegExp('[çÇ]'), 'c');
  }

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String compactar(String texto) {
    return semAcentos(texto)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
  }

  static double moedaParaDouble(String valor) {
    var t = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    bool negativo = false;

    if (t.startsWith('-')) {
      negativo = true;
      t = t.substring(1);
    }

    t = t.replaceAll('.', '').replaceAll(',', '.');

    final n = double.tryParse(t) ?? 0.0;

    return negativo ? -n : n;
  }

  static String normalizarCategoria(String categoria) {
    final c = semAcentos(categoria).toLowerCase();

    switch (c) {
      case 'vestuario':
        return 'vestuário';
      case 'saude':
      case 'health':
        return 'saúde';
      case 'servicos':
      case 'money':
        return 'serviços';
      case 'eletronicos':
        return 'eletrônicos';
      case 'supermarket':
        return 'supermercado';
      default:
        return c;
    }
  }

  static double? procurarValor(
    String texto,
    RegExp regex,
  ) {
    final m = regex.firstMatch(texto);

    if (m == null || m.group(1) == null) return null;

    return moedaParaDouble(m.group(1)!);
  }

  // ==========================================================
  // TOTAL DA FATURA
  // ==========================================================

  static double? procurarTotalFatura(String texto) {
    final normal = procurarValor(
      texto.replaceAll('\n', ''),
      RegExp(
        r'Total desta fatura\s*R?\$?\s*([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    if (normal != null) return normal;

    // Fallback para texto fragmentado.
    final c = compactar(texto);

    final m = RegExp(
      r'totaldestafatura(?:r\$)?([\d\.]+,\d{2})',
    ).firstMatch(c);

    if (m != null) {
      return moedaParaDouble(m.group(1)!);
    }

    return null;
  }

  // ==========================================================
  // SUBTOTAIS
  // ==========================================================

  static double? procurarSubtotalCompactado(
    String texto,
    String marcador,
  ) {
    final c = compactar(texto);
    final alvo = compactar(marcador);

    final pos = c.indexOf(alvo);

    if (pos < 0) return null;

    final depois = c.substring(pos + alvo.length);

    final m = RegExp(
      r'-?[\d\.]+,\d{2}',
    ).firstMatch(depois);

    if (m == null) return null;

    return moedaParaDouble(m.group(0)!);
  }

  // ==========================================================
  // PARSER DE COMPRAS - MÉTODO ORIGINAL
  // ==========================================================

  static List<Lancamento> lerComprasOriginal(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final achatado =
        texto.replaceAll('\r', '').replaceAll('\n', '');

    final inicio =
        achatado.indexOf('Lançamentos: compras e saques');

    final fim =
        achatado.indexOf('Lançamentos no cartão');

    if (inicio < 0 || fim <= inicio) {
      return resultado;
    }

    var secao = achatado.substring(inicio, fim);

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

    final categorias =
        r'(restaurante|supermercado|vestuário|vestuario|'
        r'saúde|saude|serviços|servicos|outros|lazer|'
        r'eletronicos|eletrônicos|hotel|health|money|'
        r'supermarket)';

    final regex = RegExp(
      r'(\d{2}/\d{2})'
      r'(.+?)'
      r'(?:\s(\d{2})/(\d{2}))?'
      r'(-?[\d\.]+,\d{2})'
      + categorias,
      caseSensitive: false,
    );

    for (final m in regex.allMatches(secao)) {
      var descricao = limparEspacos(m.group(2) ?? '');

      int? atual = int.tryParse(m.group(3) ?? '');
      int? total = int.tryParse(m.group(4) ?? '');

      final parcelaDescricao = RegExp(
        r'\s(\d{2})/(\d{2})$',
      ).firstMatch(descricao);

      if (parcelaDescricao != null) {
        atual = int.tryParse(parcelaDescricao.group(1)!);
        total = int.tryParse(parcelaDescricao.group(2)!);

        descricao = descricao
            .substring(0, parcelaDescricao.start)
            .trim();
      }

      final valor = m.group(5);
      final categoria = m.group(6);

      if (valor == null ||
          categoria == null ||
          descricao.isEmpty) {
        continue;
      }

      resultado.add(
        Lancamento(
          data: m.group(1) ?? '',
          descricao: descricao,
          categoria: normalizarCategoria(categoria),
          valor: moedaParaDouble(valor),
          parcelaAtual: atual,
          totalParcelas: total,
          tipo: atual != null && total != null
              ? 'Parcelada'
              : 'À vista',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PARSER DE COMPRAS - PDF FRAGMENTADO
  //
  // Remove espaços do bloco para reconstruir datas,
  // parcelas, valores e categorias quebradas pelo PDF.
  // ==========================================================

  static List<Lancamento> lerComprasFragmentadas(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final c = compactar(texto);

    const inicioAlvo = 'lancamentos:comprasesaques';

    var inicio = c.indexOf(inicioAlvo);

    // Alguns PDFs perdem os dois pontos.
    if (inicio < 0) {
      inicio = c.indexOf('lancamentoscomprasesaques');
    }

    if (inicio < 0) return resultado;

    final possiveisFins = <int>[];

    for (final alvo in [
      'lancamentosnocartao',
      'lancamentosinternacionais',
      'lancamentos:produtoseservicos',
      'comprasparceladas-proximasfaturas',
      'comprasparceladasproximasfaturas',
      'totaldoslancamentosatuais',
    ]) {
      final p = c.indexOf(alvo, inicio + 10);

      if (p > inicio) possiveisFins.add(p);
    }

    if (possiveisFins.isEmpty) return resultado;

    possiveisFins.sort();

    final fim = possiveisFins.first;

    var secao = c.substring(inicio, fim);

    secao = secao
        .replaceAll('lancamentos:comprasesaques', '')
        .replaceAll('lancamentoscomprasesaques', '')
        .replaceAll('dataestabelecimentovaloremr\$', '')
        .replaceAll('continua...', '');

    const categorias =
        r'(restaurante|supermercado|vestuario|saude|'
        r'servicos|outros|lazer|eletronicos|hotel|'
        r'health|money|supermarket)';

    final regex = RegExp(
      r'(\d{2}/\d{2})'
      r'(.+?)'
      r'(?:(\d{2})/(\d{2}))?'
      r'(-?[\d\.]+,\d{2})'
      + categorias,
    );

    for (final m in regex.allMatches(secao)) {
      var descricao = m.group(2) ?? '';

      int? atual = int.tryParse(m.group(3) ?? '');
      int? total = int.tryParse(m.group(4) ?? '');

      // Segurança para parcela que tenha ficado
      // grudada no final da descrição.
      final parcelaNoFim = RegExp(
        r'(\d{2})/(\d{2})$',
      ).firstMatch(descricao);

      if (parcelaNoFim != null) {
        atual = int.tryParse(parcelaNoFim.group(1)!);
        total = int.tryParse(parcelaNoFim.group(2)!);

        descricao = descricao
            .substring(0, parcelaNoFim.start);
      }

      final valor = m.group(5);
      final categoria = m.group(6);

      if (descricao.isEmpty ||
          valor == null ||
          categoria == null) {
        continue;
      }

      resultado.add(
        Lancamento(
          data: m.group(1) ?? '',
          descricao: descricao,
          categoria: normalizarCategoria(categoria),
          valor: moedaParaDouble(valor),
          parcelaAtual: atual,
          totalParcelas: total,
          tipo: atual != null && total != null
              ? 'Parcelada'
              : 'À vista',
          observacoes:
              'Descrição reconstruída de PDF fragmentado',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // ESCOLHA DO MELHOR PARSER
  // ==========================================================

  static List<Lancamento> lerCompras(
    String texto,
    double? totalCartao,
  ) {
    final original = lerComprasOriginal(texto);

    // Se o parser original já fecha o subtotal,
    // não mexemos nele.
    if (original.isNotEmpty && totalCartao != null) {
      final soma =
          original.fold<double>(0, (s, e) => s + e.valor);

      if ((soma - totalCartao).abs() < 0.02) {
        return original;
      }
    }

    final fragmentado =
        lerComprasFragmentadas(texto);

    if (fragmentado.isEmpty) {
      return original;
    }

    if (original.isEmpty) {
      return fragmentado;
    }

    if (totalCartao != null) {
      final somaOriginal =
          original.fold<double>(0, (s, e) => s + e.valor);

      final somaFragmentada =
          fragmentado.fold<double>(0, (s, e) => s + e.valor);

      final erroOriginal =
          (totalCartao - somaOriginal).abs();

      final erroFragmentado =
          (totalCartao - somaFragmentada).abs();

      return erroFragmentado < erroOriginal
          ? fragmentado
          : original;
    }

    return fragmentado.length > original.length
        ? fragmentado
        : original;
  }

  // ==========================================================
  // INTERNACIONAL
  //
  // IMPORTANTE:
  // totalInternacionalInformado é só conferência.
  // O lançamento usa transação + IOF.
  // ==========================================================

  static List<Lancamento> lerInternacional(
    String texto,
  ) {
    final resultado = <Lancamento>[];

    final achatado =
        texto.replaceAll('\r', '').replaceAll('\n', '');

    final compra = procurarValor(
      achatado,
      RegExp(
        r'Total transações inter\.\s*em R\$'
        r'\s*([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final iof = procurarValor(
      achatado,
      RegExp(
        r'Repasse de IOF\s*em R\$'
        r'\s*([\d\.]+,\d{2})',
        caseSensitive: false,
      ),
    );

    final compraFallback = compra ??
        procurarSubtotalCompactado(
          texto,
          'Total transações inter. em R\$',
        );

    final iofFallback = iof ??
        procurarSubtotalCompactado(
          texto,
          'Repasse de IOF em R\$',
        );

    if (compraFallback != null &&
        compraFallback.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Compra internacional',
          categoria: 'internacional',
          valor: compraFallback,
          tipo: 'Internacional',
          observacoes:
              'Transação internacional da fatura',
        ),
      );
    }

    if (iofFallback != null &&
        iofFallback.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao:
              'Repasse de IOF - transação internacional',
          categoria: 'encargos',
          valor: iofFallback,
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

    final achatado =
        texto.replaceAll('\r', '').replaceAll('\n', '');

    int inicio = achatado.indexOf(
      'Lançamentos: produtos e serviços',
    );

    int fim =
        achatado.indexOf('Total dos lançamentos atuais');

    if (inicio < 0 || fim <= inicio) {
      return resultado;
    }

    var secao = achatado.substring(inicio, fim);

    secao = secao.replaceAll(
      RegExp(
        r'Lançamentos:\s*produtos\s*e\s*serviços',
        caseSensitive: false,
      ),
      '',
    );

    final datas =
        RegExp(r'\d{2}/\d{2}').allMatches(secao).toList();

    for (int i = 0; i < datas.length; i++) {
      final atual = datas[i];

      final fimBloco = i + 1 < datas.length
          ? datas[i + 1].start
          : secao.length;

      var bloco = secao.substring(
        atual.start,
        fimBloco,
      );

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
  // ENCARGOS
  //
  // Só adiciona a diferença se houver evidência textual
  // de encargos cobrados e a diferença for positiva.
  // ==========================================================

  static Lancamento? procurarEncargos(
    String texto,
    double diferenca,
  ) {
    if (diferenca <= 0.009) return null;

    final c = compactar(texto);

    final temEncargo =
        c.contains('encargosdefinanciamento') ||
            c.contains('encargosmoratorios') ||
            c.contains('jurosrotativo') ||
            c.contains('jurosdemora') ||
            c.contains('multaporatraso');

    if (!temEncargo) return null;

    return Lancamento(
      data: '',
      descricao:
          'Encargos de financiamento / moratórios',
      categoria: 'encargos',
      valor: diferenca,
      tipo: 'Encargo',
      observacoes:
          'Encargos cobrados identificados na fatura',
    );
  }

  // ==========================================================
  // VENCIMENTO
  // ==========================================================

  static String procurarVencimento(String texto) {
    final m = RegExp(
      r'Vencimento\s*:?\s*(\d{2}/\d{2}/\d{4})',
      caseSensitive: false,
    ).firstMatch(texto);

    return m?.group(1) ?? '';
  }

  // ==========================================================
  // CARTÃO
  // ==========================================================

  static String procurarCartao(String texto) {
    final m = RegExp(
      r'Cart[aã]o\s+([Xx\d\.\s]{4,})',
      caseSensitive: false,
    ).firstMatch(texto);

    return limparEspacos(m?.group(1) ?? '');
  }

  // ==========================================================
  // PROCESSAMENTO
  // ==========================================================

  static ResultadoFatura processar(
    String texto,
  ) {
    final alertas = <String>[];

    final totalFatura =
        procurarTotalFatura(texto);

    final totalCartao =
        procurarSubtotalCompactado(
      texto,
      'Lançamentos no cartão',
    );

    final totalInternacional =
        procurarSubtotalCompactado(
      texto,
      'Total lançamentos inter. em R\$',
    );

    final totalServicos =
        procurarSubtotalCompactado(
      texto,
      'Lançamentos produtos e serviços',
    );

    final compras =
        lerCompras(texto, totalCartao);

    final internacional =
        lerInternacional(texto);

    final produtos =
        lerProdutosServicos(texto);

    final lancamentos = <Lancamento>[
      ...compras,
      ...internacional,
      ...produtos,
    ];

    // ========================================================
    // ENCARGOS REAIS
    // ========================================================

    if (totalFatura != null) {
      final somaAtual = lancamentos.fold<double>(
        0,
        (s, e) => s + e.valor,
      );

      final falta = totalFatura - somaAtual;

      final encargo =
          procurarEncargos(texto, falta);

      if (encargo != null) {
        lancamentos.add(encargo);
      }
    }

    // ========================================================
    // VALIDAÇÃO DAS COMPRAS
    // ========================================================

    final somaCompras = compras.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (compras.isEmpty) {
      alertas.add(
        'Nenhuma compra individual foi reconstruída.',
      );
    }

    if (totalCartao != null) {
      final diferencaCartao =
          totalCartao - somaCompras;

      if (diferencaCartao.abs() >= 0.02) {
        alertas.add(
          'Compras individuais não fecham o subtotal '
          '"Lançamentos no cartão". '
          'Diferença: R\$ '
          '${diferencaCartao.toStringAsFixed(2)}',
        );
      }
    }

    // ========================================================
    // VALIDAÇÃO FINAL
    // ========================================================

    final somaFinal = lancamentos.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalFatura == null) {
      alertas.add(
        'Total da fatura não identificado.',
      );
    } else {
      final diferenca =
          totalFatura - somaFinal;

      if (diferenca.abs() >= 0.02) {
        alertas.add(
          'Total ainda não conciliado. '
          'Diferença: R\$ '
          '${diferenca.toStringAsFixed(2)}',
        );
      }
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado: totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado:
          totalServicos,
      vencimento: procurarVencimento(texto),
      cartao: procurarCartao(texto),
      lancamentos: lancamentos,
      compras: compras,
      alertas: alertas,
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
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
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

  int get quantidadeIncompletas => faturas
      .where((f) => f.resultado.status == 'INCOMPLETA')
      .length;

  int get quantidadeFalhas => faturas
      .where((f) => f.resultado.falhaLeitura)
      .length;

  int get quantidadeDivergentes => faturas
      .where((f) => f.resultado.status == 'DIVERGENTE')
      .length;

  int get totalLancamentos => faturas.fold(
        0,
        (s, f) => s + f.resultado.lancamentos.length,
      );

  int get totalParceladas => faturas.fold(
        0,
        (s, f) => s + f.resultado.quantidadeParceladas,
      );

  double get valorTotalFaturas => faturas.fold(
        0.0,
        (s, f) => s + (f.resultado.totalFatura ?? 0),
      );

  double get somaTotalLancamentos => faturas.fold(
        0.0,
        (s, f) => s + f.resultado.soma,
      );

  bool get todasConciliadas =>
      faturas.isNotEmpty &&
      faturas.every((f) => f.resultado.conciliada);

  Future<void> selecionarFaturas() async {
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
    });

    for (int i = 0; i < escolha.files.length; i++) {
      final arquivo = escolha.files[i];

      setState(() {
        status =
            'Analisando ${i + 1} de '
            '${escolha.files.length}\n'
            '${arquivo.name}';
      });

      try {
        if (arquivo.path == null) {
          throw Exception('Arquivo inacessível');
        }

        final bytes =
            await File(arquivo.path!).readAsBytes();

        final documento =
            PdfDocument(inputBytes: bytes);

        final texto =
            PdfTextExtractor(documento).extractText();

        documento.dispose();

        final resultado =
            ParserItau.processar(texto);

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: resultado,
          ),
        );
      } catch (e) {
        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: ResultadoFatura(
              totalFatura: null,
              lancamentos: const [],
              compras: const [],
              alertas: [
                'Falha ao processar: $e',
              ],
            ),
          ),
        );
      }
    }

    if (!mounted) return;

    setState(() {
      processando = false;

      status =
          '${faturas.length} fatura(s) processada(s).\n'
          '$quantidadeConciliadas conciliada(s), '
          '$quantidadeIncompletas incompleta(s), '
          '$quantidadeDivergentes divergente(s), '
          '$quantidadeFalhas falha(s).';
    });
  }

  Future<void> gerarExcel() async {
    if (!todasConciliadas) return;

    setState(() {
      gerandoExcel = true;
    });

    try {
      final excel = Excel.createExcel();

      final sheet = excel['Lançamentos'];

      sheet.appendRow([
        TextCellValue('Fatura / Arquivo'),
        TextCellValue('Vencimento'),
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
          sheet.appendRow([
            TextCellValue(fatura.arquivo),
            TextCellValue(fatura.resultado.vencimento),
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

      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('TOTAL'),
        TextCellValue(''),
        DoubleCellValue(somaTotalLancamentos),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ]);

      final conferencia = excel['Conferência'];

      conferencia.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Total da fatura'),
        TextCellValue('Subtotal cartão'),
        TextCellValue('Soma compras individuais'),
        TextCellValue('Diferença cartão'),
        TextCellValue('Soma geral'),
        TextCellValue('Diferença geral'),
        TextCellValue('Lançamentos'),
        TextCellValue('Parceladas'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r = fatura.resultado;

        conferencia.appendRow([
          TextCellValue(fatura.arquivo),
          DoubleCellValue(r.totalFatura ?? 0),
          DoubleCellValue(r.totalCartaoInformado ?? 0),
          DoubleCellValue(r.somaCompras),
          DoubleCellValue(r.diferencaCartao ?? 0),
          DoubleCellValue(r.soma),
          DoubleCellValue(r.diferenca ?? 0),
          IntCellValue(r.lancamentos.length),
          IntCellValue(r.quantidadeParceladas),
          TextCellValue(r.status),
        ]);
      }

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes = excel.encode();

      if (bytes == null) {
        throw Exception('Falha ao criar Excel');
      }

      final pasta = await getTemporaryDirectory();

      final arquivo = File(
        '${pasta.path}/Faturas_Itau_conferidas.xlsx',
      );

      await arquivo.writeAsBytes(bytes);

      await Share.shareXFiles(
        [
          XFile(
            arquivo.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      );
    } finally {
      if (mounted) {
        setState(() {
          gerandoExcel = false;
        });
      }
    }
  }

  String dinheiro(double valor) {
    final negativo = valor < 0;

    final partes =
        valor.abs().toStringAsFixed(2).split('.');

    var inteiro = partes[0];

    final buffer = StringBuffer();

    for (int i = 0; i < inteiro.length; i++) {
      final restante = inteiro.length - i;

      buffer.write(inteiro[i]);

      if (restante > 1 && restante % 3 == 1) {
        buffer.write('.');
      }
    }

    return '${negativo ? '-' : ''}R\$ '
        '${buffer.toString()},${partes[1]}';
  }

  Widget linha(String nome, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(nome)),
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

  Color cor(ResultadoFatura r) {
    if (r.conciliada) return Colors.green;
    if (r.falhaLeitura) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferidor de Faturas'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed:
                processando ? null : selecionarFaturas,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text(
              'Selecionar faturas PDF',
            ),
          ),

          const SizedBox(height: 15),

          if (processando)
            const LinearProgressIndicator(),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(status),
            ),
          ),

          if (faturas.isNotEmpty) ...[
            const SizedBox(height: 15),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    linha(
                      'Faturas',
                      '${faturas.length}',
                    ),
                    linha(
                      'Conciliadas',
                      '$quantidadeConciliadas',
                    ),
                    linha(
                      'Incompletas',
                      '$quantidadeIncompletas',
                    ),
                    linha(
                      'Divergentes',
                      '$quantidadeDivergentes',
                    ),
                    linha(
                      'Falhas',
                      '$quantidadeFalhas',
                    ),
                    const Divider(),
                    linha(
                      'Total das faturas',
                      dinheiro(valorTotalFaturas),
                    ),
                    linha(
                      'Soma dos lançamentos',
                      dinheiro(somaTotalLancamentos),
                    ),
                    linha(
                      'Lançamentos',
                      '$totalLancamentos',
                    ),
                    linha(
                      'Compras parceladas',
                      '$totalParceladas',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            FilledButton.icon(
              onPressed:
                  todasConciliadas && !gerandoExcel
                      ? gerarExcel
                      : null,
              icon: const Icon(Icons.table_view),
              label: const Text(
                'Gerar Excel consolidado',
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Conferência por fatura',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            ...faturas.map((fatura) {
              final r = fatura.resultado;

              return Card(
                margin:
                    const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        fatura.arquivo,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      if (r.vencimento.isNotEmpty)
                        Text(
                          'Vencimento: ${r.vencimento}',
                        ),

                      const SizedBox(height: 12),

                      linha(
                        'Total da fatura',
                        r.totalFatura == null
                            ? 'Não identificado'
                            : dinheiro(r.totalFatura!),
                      ),

                      linha(
                        'Subtotal cartão',
                        r.totalCartaoInformado == null
                            ? 'Não identificado'
                            : dinheiro(
                                r.totalCartaoInformado!,
                              ),
                      ),

                      linha(
                        'Compras reconstruídas',
                        dinheiro(r.somaCompras),
                      ),

                      linha(
                        'Diferença do cartão',
                        r.diferencaCartao == null
                            ? 'Não calculada'
                            : dinheiro(
                                r.diferencaCartao!,
                              ),
                      ),

                      const Divider(),

                      linha(
                        'Soma geral',
                        dinheiro(r.soma),
                      ),

                      linha(
                        'Diferença geral',
                        r.diferenca == null
                            ? 'Não calculada'
                            : dinheiro(r.diferenca!),
                      ),

                      linha(
                        'Lançamentos',
                        '${r.lancamentos.length}',
                      ),

                      linha(
                        'Compras individuais',
                        '${r.compras.length}',
                      ),

                      linha(
                        'Parceladas',
                        '${r.quantidadeParceladas}',
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Icon(
                            r.conciliada
                                ? Icons.check_circle
                                : r.falhaLeitura
                                    ? Icons.error
                                    : Icons.warning_amber,
                            color: cor(r),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            r.status,
                            style: TextStyle(
                              color: cor(r),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      if (r.alertas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...r.alertas.map(
                          (a) => Padding(
                            padding:
                                const EdgeInsets.only(
                              bottom: 4,
                            ),
                            child: Text('• $a'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
