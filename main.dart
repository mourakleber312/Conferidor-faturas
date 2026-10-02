import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const ConferidorApp());

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

  bool get parcelada => parcelaAtual != null && totalParcelas != null;
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

  double get soma => lancamentos.fold(0.0, (s, e) => s + e.valor);
  double get somaCompras => compras.fold(0.0, (s, e) => s + e.valor);

  double? get diferenca =>
      totalFatura == null ? null : totalFatura! - soma;

  double? get diferencaCartao => totalCartaoInformado == null
      ? null
      : totalCartaoInformado! - somaCompras;

  int get quantidadeParceladas => compras.where((e) => e.parcelada).length;

  bool get comprasReconstruidas {
    if (compras.isEmpty) return false;
    if (totalCartaoInformado == null) return true;
    return (totalCartaoInformado! - somaCompras).abs() < 0.02;
  }

  bool get totalConciliado =>
      totalFatura != null && diferenca != null && diferenca!.abs() < 0.02;

  bool get conciliada => totalConciliado && comprasReconstruidas;
  bool get falhaLeitura => totalFatura == null && compras.isEmpty;

  String get status {
    if (falhaLeitura) return 'FALHA DE LEITURA';
    if (conciliada) return 'CONCILIADA';
    if (totalConciliado && !comprasReconstruidas) return 'INCOMPLETA';
    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;
  final String textoBruto;

  FaturaProcessada({
    required this.arquivo,
    required this.resultado,
    required this.textoBruto,
  });
}

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

  static String limparEspacos(String texto) =>
      texto.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String compactar(String texto) =>
      semAcentos(texto).toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static double moedaParaDouble(String valor) {
    var t = valor.replaceAll('R\$', '').replaceAll(' ', '').trim();
    var negativo = false;
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

  static double? procurarTotalFatura(String texto) {
    final c = compactar(texto);
    final m = RegExp(
      r'totaldestafatura(?:r\$)?(-?[\d\.]+,\d{2})',
    ).firstMatch(c);
    return m == null ? null : moedaParaDouble(m.group(1)!);
  }

  static double? procurarSubtotal(String texto, List<String> marcadores) {
    final c = compactar(texto);
    for (final marcador in marcadores) {
      final alvo = compactar(marcador);
      final pos = c.indexOf(alvo);
      if (pos < 0) continue;
      final depois = c.substring(pos + alvo.length);
      final m = RegExp(r'-?[\d\.]+,\d{2}').firstMatch(depois);
      if (m != null) return moedaParaDouble(m.group(0)!);
    }
    return null;
  }

  static String procurarVencimento(String texto) {
    final c = compactar(texto);
    final m = RegExp(r'vencimento:?(\d{2}/\d{2}/\d{4})').firstMatch(c);
    return m?.group(1) ?? '';
  }

  static String procurarCartao(String texto) {
    final m = RegExp(
      r'Cart[aã]o\s+([Xx\d\.\s]{4,})',
      caseSensitive: false,
    ).firstMatch(texto);
    return limparEspacos(m?.group(1) ?? '');
  }

  static const categorias = <String>[
    'restaurante',
    'supermercado',
    'vestuario',
    'saude',
    'servicos',
    'outros',
    'lazer',
    'eletronicos',
    'hotel',
    'health',
    'money',
    'supermarket',
  ];

  static String categoriaNoTrecho(String trecho) {
    final c = compactar(trecho);
    for (final cat in categorias) {
      if (c.contains(cat)) return normalizarCategoria(cat);
    }
    return '';
  }

  static bool dataValida(String data) {
    final p = data.split('/');
    if (p.length != 2) return false;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return d != null && m != null && d >= 1 && d <= 31 && m >= 1 && m <= 12;
  }

  static List<Lancamento> lerComprasOriginal(String texto) {
    final resultado = <Lancamento>[];
    final achatado = texto.replaceAll('\r', '').replaceAll('\n', '');

    var inicio = achatado.indexOf('Lançamentos: compras e saques');
    var fim = achatado.indexOf('Lançamentos no cartão');

    if (inicio < 0 || fim <= inicio) return resultado;

    var secao = achatado.substring(inicio, fim)
      ..replaceAll('continua...', '');

    final cats =
        r'(restaurante|supermercado|vestuário|vestuario|saúde|saude|'
        r'serviços|servicos|outros|lazer|eletronicos|eletrônicos|hotel|'
        r'health|money|supermarket)';

    final regex = RegExp(
      r'(\d{2}/\d{2})(.+?)(?:\s(\d{2})/(\d{2}))?'
      r'(-?[\d\.]+,\d{2})' + cats,
      caseSensitive: false,
    );

    for (final m in regex.allMatches(secao)) {
      var descricao = limparEspacos(m.group(2) ?? '');
      var atual = int.tryParse(m.group(3) ?? '');
      var total = int.tryParse(m.group(4) ?? '');

      final parcelaDescricao =
          RegExp(r'\s(\d{1,2})/(\d{1,2})$').firstMatch(descricao);
      if (parcelaDescricao != null) {
        atual = int.tryParse(parcelaDescricao.group(1)!);
        total = int.tryParse(parcelaDescricao.group(2)!);
        descricao = descricao.substring(0, parcelaDescricao.start).trim();
      }

      if (descricao.isEmpty || m.group(5) == null || m.group(6) == null) {
        continue;
      }

      resultado.add(
        Lancamento(
          data: m.group(1)!,
          descricao: descricao,
          categoria: normalizarCategoria(m.group(6)!),
          valor: moedaParaDouble(m.group(5)!),
          parcelaAtual: atual,
          totalParcelas: total,
          tipo: atual != null && total != null ? 'Parcelada' : 'À vista',
        ),
      );
    }
    return resultado;
  }

  // Converte o PDF "letra por letra" em uma representação compacta.
  // Em seguida o parser trabalha com as âncoras: data -> próxima data.
  static String reconstruirFragmentado(String texto) {
    var t = semAcentos(texto)
        .toLowerCase()
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\u00A0', ' ');

    // Datas/parcelas: "25 /04" -> "25/04", "04 /1 2" -> "04/12".
    t = t.replaceAll(RegExp(r'\s*/\s*'), '/');
    t = t.replaceAll(RegExp(r'\s*,\s*'), ',');
    t = t.replaceAll(RegExp(r'\s*\.\s*'), '.');

    for (var i = 0; i < 8; i++) {
      t = t.replaceAllMapped(
        RegExp(r'(?<=/)(\d)\s+(\d)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );
      t = t.replaceAllMapped(
        RegExp(r'(\d)\s+(\d)(?=/)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );
      t = t.replaceAllMapped(
        RegExp(r'(?<=,)(\d)\s+(\d)'),
        (m) => '${m.group(1)}${m.group(2)}',
      );
    }

    return limparEspacos(t);
  }

  // Cria uma versão sem espaços para capturar valores fragmentados.
  // Mantemos "/" e "," porque são essenciais para data/parcela/valor.
  static String compactarSecao(String texto) =>
      reconstruirFragmentado(texto).replaceAll(RegExp(r'\s+'), '');

  static List<Lancamento> lerComprasFragmentadas(String texto) {
    final resultado = <Lancamento>[];
    final c = compactarSecao(texto);

    var inicio = c.indexOf('lancamentos:comprasesaques');
    if (inicio < 0) inicio = c.indexOf('lancamentoscomprasesaques');
    if (inicio < 0) return resultado;

    final fins = <int>[];
    for (final marcador in <String>[
      'lancamentosnocartao',
      'lancamentosinternacionais',
      'lancamentos:produtoseservicos',
      'lancamentosprodutoseservicos',
      'comprasparceladas-proximasfaturas',
      'comprasparceladasproximasfaturas',
      'totaldoslancamentosatuais',
    ]) {
      final p = c.indexOf(marcador, inicio + 10);
      if (p > inicio) fins.add(p);
    }
    if (fins.isEmpty) return resultado;
    fins.sort();

    var secao = c.substring(inicio, fins.first);
    secao = secao
        .replaceAll('lancamentos:comprasesaques', '')
        .replaceAll('lancamentoscomprasesaques', '')
        .replaceAll('dataestabelecimentovaloremr\$', '')
        .replaceAll('dataestabelecimentovaloremr', '')
        .replaceAll('continua...', '');

    // Uma data válida é usada como âncora. Parcelas com mês > 12
    // não passam por dataValida e não viram início de lançamento.
    final candidatos = RegExp(r'\d{2}/\d{2}').allMatches(secao).toList();
    final datas = candidatos
        .where((m) => dataValida(m.group(0) ?? ''))
        .toList();

    for (var i = 0; i < datas.length; i++) {
      final dm = datas[i];
      final data = dm.group(0)!;
      final fimBloco =
          i + 1 < datas.length ? datas[i + 1].start : secao.length;
      if (fimBloco <= dm.end) continue;

      var bloco = secao.substring(dm.end, fimBloco);

      // Valor: último número com centavos do bloco.
      final valores =
          RegExp(r'-?\d[\d\.]*,\d{2}').allMatches(bloco).toList();
      if (valores.isEmpty) continue;

      final vm = valores.last;
      final valorTexto = vm.group(0)!;
      var antes = bloco.substring(0, vm.start);
      final depois = bloco.substring(vm.end);

      int? parcelaAtual;
      int? totalParcelas;

      final parcelas =
          RegExp(r'(\d{1,2})/(\d{1,2})').allMatches(antes).toList();

      // A parcela costuma ser o último xx/yy antes do valor.
      if (parcelas.isNotEmpty) {
        final pm = parcelas.last;
        final pa = int.tryParse(pm.group(1) ?? '');
        final pt = int.tryParse(pm.group(2) ?? '');

        if (pa != null &&
            pt != null &&
            pa >= 1 &&
            pt >= pa &&
            pt <= 48) {
          parcelaAtual = pa;
          totalParcelas = pt;
          antes = antes.replaceRange(pm.start, pm.end, '');
        }
      }

      var categoria = categoriaNoTrecho(depois);
      if (categoria.isEmpty) categoria = categoriaNoTrecho(antes);

      var descricao = antes;
      for (final cat in categorias) {
        descricao = descricao.replaceAll(cat, '');
      }
      descricao = limparEspacos(descricao);

      if (descricao.isEmpty) continue;
      if (descricao.contains('totaldoslancamentos')) continue;

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: categoria,
          valor: moedaParaDouble(valorTexto),
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: parcelaAtual != null && totalParcelas != null
              ? 'Parcelada'
              : 'À vista',
          observacoes: 'Reconstruído de PDF Itaú fragmentado',
        ),
      );
    }

    final unicos = <Lancamento>[];
    final chaves = <String>{};
    for (final item in resultado) {
      final chave =
          '${item.data}|${compactar(item.descricao)}|'
          '${item.valor.toStringAsFixed(2)}|'
          '${item.parcelaAtual ?? ''}|${item.totalParcelas ?? ''}';
      if (chaves.add(chave)) unicos.add(item);
    }
    return unicos;
  }

  static List<Lancamento> lerCompras(String texto, double? totalCartao) {
    final original = lerComprasOriginal(texto);
    final fragmentado = lerComprasFragmentadas(texto);

    if (totalCartao == null) {
      return fragmentado.length > original.length ? fragmentado : original;
    }

    double erro(List<Lancamento> lista) {
      final soma = lista.fold<double>(0, (s, e) => s + e.valor);
      return (totalCartao - soma).abs();
    }

    if (original.isNotEmpty && erro(original) < 0.02) return original;
    if (fragmentado.isNotEmpty && erro(fragmentado) < 0.02) {
      return fragmentado;
    }

    if (original.isEmpty) return fragmentado;
    if (fragmentado.isEmpty) return original;

    return erro(fragmentado) < erro(original) ? fragmentado : original;
  }

  static List<Lancamento> lerInternacional(String texto) {
    final resultado = <Lancamento>[];

    final compra = procurarSubtotal(
      texto,
      const [
        'Total transações inter. em R\$',
        'Total transacoes inter. em R\$',
      ],
    );

    final iof = procurarSubtotal(
      texto,
      const [
        'Repasse de IOF em R\$',
        'Repasse de IOF',
      ],
    );

    if (compra != null && compra.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Compra internacional',
          categoria: 'internacional',
          valor: compra,
          tipo: 'Internacional',
          observacoes: 'Total das transações internacionais da fatura',
        ),
      );
    }

    if (iof != null && iof.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Repasse de IOF - transação internacional',
          categoria: 'encargos',
          valor: iof,
          tipo: 'Encargo / IOF',
          observacoes: 'IOF das transações internacionais',
        ),
      );
    }

    return resultado;
  }

  static List<Lancamento> lerProdutosServicos(
    String texto,
    double? totalServicos,
  ) {
    final resultado = <Lancamento>[];
    final achatado = texto.replaceAll('\r', '').replaceAll('\n', '');

    var inicio = achatado.indexOf('Lançamentos: produtos e serviços');
    var fim = achatado.indexOf('Total dos lançamentos atuais');

    if (inicio >= 0 && fim > inicio) {
      final secao = achatado.substring(inicio, fim);
      final datas = RegExp(r'\d{2}/\d{2}').allMatches(secao).toList();

      for (var i = 0; i < datas.length; i++) {
        final atual = datas[i];
        final fimBloco =
            i + 1 < datas.length ? datas[i + 1].start : secao.length;
        var bloco = secao.substring(atual.start, fimBloco);
        if (bloco.length < 5) continue;

        final data = bloco.substring(0, 5);
        bloco = bloco.substring(5);

        final vm = RegExp(r'(-?[\d\.]+,\d{2})').firstMatch(bloco);
        if (vm == null) continue;

        var descricao = limparEspacos(bloco.substring(0, vm.start));
        if (descricao.isEmpty) descricao = 'Produto/serviço Itaú';

        resultado.add(
          Lancamento(
            data: data,
            descricao: descricao,
            categoria: 'produtos e serviços',
            valor: moedaParaDouble(vm.group(1)!),
            tipo: 'Produto/Serviço',
          ),
        );
      }
    }

    // Se os itens individuais não puderam ser lidos, não inventamos
    // descrições. O subtotal líquido pode ser usado como lançamento
    // apenas para representar fielmente a seção da própria fatura.
    if (resultado.isEmpty &&
        totalServicos != null &&
        totalServicos.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Subtotal produtos e serviços',
          categoria: 'produtos e serviços',
          valor: totalServicos,
          tipo: 'Produto/Serviço',
          observacoes:
              'Itens individuais não legíveis; valor é o subtotal informado pelo Itaú',
        ),
      );
    }

    return resultado;
  }

  static ResultadoFatura processar(String texto) {
    final alertas = <String>[];

    final totalFatura = procurarTotalFatura(texto);
    final totalCartao = procurarSubtotal(
      texto,
      const ['Lançamentos no cartão', 'Lancamentos no cartao'],
    );
    final totalInternacional = procurarSubtotal(
      texto,
      const [
        'Total lançamentos inter. em R\$',
        'Total lancamentos inter. em R\$',
      ],
    );
    final totalServicos = procurarSubtotal(
      texto,
      const [
        'Lançamentos produtos e serviços',
        'Lancamentos produtos e servicos',
      ],
    );

    final compras = lerCompras(texto, totalCartao);
    final internacional = lerInternacional(texto);
    final produtos = lerProdutosServicos(texto, totalServicos);

    final lancamentos = <Lancamento>[
      ...compras,
      ...internacional,
      ...produtos,
    ];

    final somaCompras = compras.fold<double>(0, (s, e) => s + e.valor);

    if (compras.isEmpty) {
      alertas.add('Nenhuma compra individual foi reconstruída.');
    }

    if (totalCartao != null) {
      final dif = totalCartao - somaCompras;
      if (dif.abs() >= 0.02) {
        alertas.add(
          'Compras individuais não fecham "Lançamentos no cartão". '
          'Diferença: R\$ ${dif.toStringAsFixed(2)}',
        );
      }
    }

    final somaFinal = lancamentos.fold<double>(0, (s, e) => s + e.valor);

    if (totalFatura == null) {
      alertas.add('Total da fatura não identificado.');
    } else {
      final dif = totalFatura - somaFinal;
      if (dif.abs() >= 0.02) {
        alertas.add(
          'Total da fatura ainda não conciliado. '
          'Diferença: R\$ ${dif.toStringAsFixed(2)}',
        );
      }
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado: totalCartao,
      totalInternacionalInformado: totalInternacional,
      totalServicosInformado: totalServicos,
      vencimento: procurarVencimento(texto),
      cartao: procurarCartao(texto),
      lancamentos: lancamentos,
      compras: compras,
      alertas: alertas,
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
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
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
  bool processando = false;
  bool gerandoExcel = false;
  String status = 'Selecione uma ou mais faturas Itaú em PDF.';
  final List<FaturaProcessada> faturas = [];

  int get quantidadeConciliadas =>
      faturas.where((f) => f.resultado.conciliada).length;
  int get quantidadeIncompletas =>
      faturas.where((f) => f.resultado.status == 'INCOMPLETA').length;
  int get quantidadeFalhas =>
      faturas.where((f) => f.resultado.falhaLeitura).length;
  int get quantidadeDivergentes =>
      faturas.where((f) => f.resultado.status == 'DIVERGENTE').length;

  int get totalLancamentos =>
      faturas.fold(0, (s, f) => s + f.resultado.lancamentos.length);
  int get totalParceladas =>
      faturas.fold(0, (s, f) => s + f.resultado.quantidadeParceladas);

  double get valorTotalFaturas =>
      faturas.fold(0.0, (s, f) => s + (f.resultado.totalFatura ?? 0));
  double get somaTotalLancamentos =>
      faturas.fold(0.0, (s, f) => s + f.resultado.soma);

  bool get todasConciliadas =>
      faturas.isNotEmpty && faturas.every((f) => f.resultado.conciliada);

  Future<void> selecionarFaturas() async {
    final escolha = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (escolha == null || escolha.files.isEmpty) return;

    setState(() {
      processando = true;
      faturas.clear();
    });

    for (var i = 0; i < escolha.files.length; i++) {
      final arquivo = escolha.files[i];

      setState(() {
        status =
            'Analisando ${i + 1} de ${escolha.files.length}\n${arquivo.name}';
      });

      try {
        if (arquivo.path == null) throw Exception('Arquivo inacessível');

        final bytes = await File(arquivo.path!).readAsBytes();
        final documento = PdfDocument(inputBytes: bytes);
        final texto = PdfTextExtractor(documento).extractText();
        documento.dispose();

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: ParserItau.processar(texto),
            textoBruto: texto,
          ),
        );
      } catch (e) {
        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            textoBruto: '',
            resultado: ResultadoFatura(
              totalFatura: null,
              lancamentos: const [],
              compras: const [],
              alertas: ['Falha ao processar: $e'],
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

  Future<void> gerarDiagnostico(FaturaProcessada fatura) async {
    final r = fatura.resultado;
    final b = StringBuffer();

    b.writeln('DIAGNÓSTICO - CONFERIDOR DE FATURAS ITAÚ');
    b.writeln('Arquivo: ${fatura.arquivo}');
    b.writeln('Status: ${r.status}');
    b.writeln('Vencimento: ${r.vencimento}');
    b.writeln('Total da fatura: ${r.totalFatura}');
    b.writeln('Subtotal cartão: ${r.totalCartaoInformado}');
    b.writeln('Soma compras: ${r.somaCompras}');
    b.writeln('Diferença cartão: ${r.diferencaCartao}');
    b.writeln('Soma geral: ${r.soma}');
    b.writeln('Diferença geral: ${r.diferenca}');
    b.writeln('Compras: ${r.compras.length}');
    b.writeln('Parceladas: ${r.quantidadeParceladas}');
    b.writeln('\nALERTAS');
    for (final a in r.alertas) {
      b.writeln('- $a');
    }

    b.writeln('\nCOMPRAS RECONSTRUÍDAS');
    for (final item in r.compras) {
      b.writeln(
        '${item.data} | ${item.descricao} | ${item.valor.toStringAsFixed(2)} | '
        '${item.parcelaAtual ?? ''}/${item.totalParcelas ?? ''} | '
        '${item.categoria}',
      );
    }

    b.writeln('\nTEXTO RECONSTRUÍDO');
    b.writeln(ParserItau.reconstruirFragmentado(fatura.textoBruto));
    b.writeln('\nTEXTO BRUTO');
    b.writeln(fatura.textoBruto);

    final pasta = await getTemporaryDirectory();
    final nome =
        fatura.arquivo.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final arq = File('${pasta.path}/diagnostico_$nome.txt');
    await arq.writeAsString(b.toString());

    await Share.shareXFiles([XFile(arq.path, mimeType: 'text/plain')]);
  }

  Future<void> gerarExcel() async {
    if (!todasConciliadas) return;
    setState(() => gerandoExcel = true);

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
        TextCellValue('Quantidade total de parcelas'),
        TextCellValue('À vista / Parcelada'),
        TextCellValue('Observações'),
      ]);

      for (final fatura in faturas) {
        for (final item in fatura.resultado.lancamentos) {
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

      final conf = excel['Conferência'];
      conf.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Valor total da fatura'),
        TextCellValue('Subtotal cartão'),
        TextCellValue('Soma compras individuais'),
        TextCellValue('Diferença cartão'),
        TextCellValue('Soma dos lançamentos'),
        TextCellValue('Diferença'),
        TextCellValue('Quantidade de lançamentos'),
        TextCellValue('Compras parceladas'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r = fatura.resultado;
        conf.appendRow([
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

      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Falha ao criar Excel');

      final pasta = await getTemporaryDirectory();
      final arq = File('${pasta.path}/Faturas_Itau_conferidas.xlsx');
      await arq.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(
          arq.path,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar Excel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => gerandoExcel = false);
    }
  }

  String dinheiro(double valor) {
    final negativo = valor < 0;
    final partes = valor.abs().toStringAsFixed(2).split('.');
    final inteiro = partes[0];
    final b = StringBuffer();

    for (var i = 0; i < inteiro.length; i++) {
      final restante = inteiro.length - i;
      b.write(inteiro[i]);
      if (restante > 1 && restante % 3 == 1) b.write('.');
    }

    return '${negativo ? '-' : ''}R\$ ${b.toString()},${partes[1]}';
  }

  Widget linha(String nome, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(nome)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
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
      appBar: AppBar(title: const Text('Conferidor de Faturas')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: processando ? null : selecionarFaturas,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Selecionar faturas PDF'),
          ),
          const SizedBox(height: 15),
          if (processando) const LinearProgressIndicator(),
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
                    linha('Faturas', '${faturas.length}'),
                    linha('Conciliadas', '$quantidadeConciliadas'),
                    linha('Incompletas', '$quantidadeIncompletas'),
                    linha('Divergentes', '$quantidadeDivergentes'),
                    linha('Falhas', '$quantidadeFalhas'),
                    const Divider(),
                    linha('Total das faturas', dinheiro(valorTotalFaturas)),
                    linha(
                      'Soma dos lançamentos',
                      dinheiro(somaTotalLancamentos),
                    ),
                    linha('Lançamentos', '$totalLancamentos'),
                    linha('Compras parceladas', '$totalParceladas'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed:
                  todasConciliadas && !gerandoExcel ? gerarExcel : null,
              icon: const Icon(Icons.table_view),
              label: Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : 'Gerar Excel consolidado',
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'Conferência por fatura',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            ...faturas.map((fatura) {
              final r = fatura.resultado;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fatura.arquivo,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (r.vencimento.isNotEmpty)
                        Text('Vencimento: ${r.vencimento}'),
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
                            : dinheiro(r.totalCartaoInformado!),
                      ),
                      linha('Compras reconstruídas', dinheiro(r.somaCompras)),
                      linha(
                        'Diferença do cartão',
                        r.diferencaCartao == null
                            ? 'Não calculada'
                            : dinheiro(r.diferencaCartao!),
                      ),
                      const Divider(),
                      linha('Soma geral', dinheiro(r.soma)),
                      linha(
                        'Diferença geral',
                        r.diferenca == null
                            ? 'Não calculada'
                            : dinheiro(r.diferenca!),
                      ),
                      linha('Lançamentos', '${r.lancamentos.length}'),
                      linha('Compras individuais', '${r.compras.length}'),
                      linha('Parceladas', '${r.quantidadeParceladas}'),
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
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $a'),
                          ),
                        ),
                      ],
                      if (!r.conciliada) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => gerarDiagnostico(fatura),
                          icon: const Icon(Icons.bug_report),
                          label: const Text('Gerar diagnóstico'),
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
