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
    final negativo = t.startsWith('-');
    if (negativo) t = t.substring(1);
    t = t.replaceAll('.', '').replaceAll(',', '.');
    final n = double.tryParse(t) ?? 0.0;
    return negativo ? -n : n;
  }

  static String normalizarCategoria(String categoria) {
    final c = semAcentos(categoria).toLowerCase().trim();
    const mapa = <String, String>{
      'vestuario': 'vestuário',
      'saude': 'saúde',
      'servicos': 'serviços',
      'eletronicos': 'eletrônicos',
      'supermarket': 'supermercado',
      'health': 'saúde',
      'money': 'serviços',
    };
    return mapa[c] ?? c;
  }

  static bool dataValida(String data) {
    final p = data.split('/');
    if (p.length != 2) return false;
    final d = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return d != null && m != null && d >= 1 && d <= 31 && m >= 1 && m <= 12;
  }

  static double? procurarTotalFatura(String texto) {
    final c = compactar(texto);
    final m = RegExp(r'totaldestafatura(?:r\$)?(-?[\d\.]+,\d{2})').firstMatch(c);
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
    final linhas = texto.replaceAll('\r', '').split('\n');
    for (final linha in linhas) {
      final m = RegExp(r'Vencimento:\s*(\d{2}/\d{2}/\d{4})',
              caseSensitive: false)
          .firstMatch(linha);
      if (m != null) return m.group(1)!;
    }
    final c = compactar(texto);
    return RegExp(r'vencimento:?(\d{2}/\d{2}/\d{4})')
            .firstMatch(c)
            ?.group(1) ??
        '';
  }

  static String procurarCartao(String texto) {
    final m = RegExp(r'Cart[aã]o\s+([Xx\d\.\s]{4,})',
            caseSensitive: false)
        .firstMatch(texto);
    return limparEspacos(m?.group(1) ?? '');
  }

  static const categoriasConhecidas = <String>[
    'restaurante',
    'supermercado',
    'vestuario',
    'vestuário',
    'saude',
    'saúde',
    'servicos',
    'serviços',
    'outros',
    'lazer',
    'eletronicos',
    'eletrônicos',
    'hotel',
    'transporte',
    'automobile',
    'health',
    'money',
    'supermarket',
  ];

  static String categoriaDaLinhaSeguinte(String linha) {
    final l = limparEspacos(linha);
    if (l.isEmpty) return '';
    final primeiro = l.split(' ').first;
    final p = semAcentos(primeiro).toLowerCase();
    for (final cat in categoriasConhecidas) {
      if (p == semAcentos(cat).toLowerCase()) {
        return normalizarCategoria(primeiro);
      }
    }
    return '';
  }

  static bool linhaEhCabecalhoOuTotal(String linha) {
    final c = compactar(linha);
    return c.contains('dataestabelecimentovaloremr') ||
        c.contains('lancamentosnocartao') ||
        c.contains('totaldoslancamentos') ||
        c.contains('proximafatura') ||
        c.contains('demaisfaturas') ||
        c.contains('limitesdecredito');
  }

  // Parser v4: o layoutText do Syncfusion preserva os lançamentos do Itaú
  // como linhas. Cada compra válida começa por DD/MM e termina em valor.
  // Isso evita fundir 2 ou 3 compras que aparecem próximas no PDF.
  static List<Lancamento> lerComprasPorLinhas(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');
    final resultado = <Lancamento>[];
    bool dentro = false;

    final rx = RegExp(
      r'^\s*(\d{2}/\d{2})\s+(.+?)\s+(-?[\d\.]+,\d{2})\s*$',
      caseSensitive: false,
    );
    final rxParcelaFim = RegExp(r'\s+(\d{1,2})/(\d{1,2})\s*$');

    for (var i = 0; i < linhas.length; i++) {
      final linha = limparEspacos(linhas[i]);
      final c = compactar(linha);

      if (c.contains('lancamentos:comprasesaques') ||
          c.contains('lancamentoscomprasesaques')) {
        dentro = true;
        continue;
      }
      if (!dentro) continue;

      if (c.contains('lancamentosnocartao')) break;
      if (linhaEhCabecalhoOuTotal(linha)) continue;

      final m = rx.firstMatch(linha);
      if (m == null) continue;

      final data = m.group(1)!;
      if (!dataValida(data)) continue;

      var descricao = limparEspacos(m.group(2)!);
      final valor = moedaParaDouble(m.group(3)!);

      // Proteção contra números de resumo/limite capturados como compra.
      if (valor.abs() > 50000) continue;

      int? parcelaAtual;
      int? totalParcelas;
      final pm = rxParcelaFim.firstMatch(descricao);
      if (pm != null) {
        final pa = int.tryParse(pm.group(1)!);
        final pt = int.tryParse(pm.group(2)!);
        if (pa != null &&
            pt != null &&
            pa >= 1 &&
            pt >= pa &&
            pt <= 60) {
          parcelaAtual = pa;
          totalParcelas = pt;
          descricao = limparEspacos(descricao.substring(0, pm.start));
        }
      }

      if (descricao.isEmpty) continue;
      final descCompacta = compactar(descricao);
      if (descCompacta.startsWith('pagamento') ||
          descCompacta.contains('totaldospagamentos')) {
        continue;
      }

      var categoria = '';
      if (i + 1 < linhas.length) {
        categoria = categoriaDaLinhaSeguinte(linhas[i + 1]);
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: categoria.isEmpty ? 'outros' : categoria,
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: parcelaAtual != null && totalParcelas != null
              ? 'Parcelada'
              : 'À vista',
          observacoes: 'Parser v4 - linha preservada do PDF Itaú',
        ),
      );
    }
    return resultado;
  }

  // Fallback para PDFs em que o layoutText não preserva linhas.
  // Mantém a estratégia antiga, mas só é usada se ela conciliar melhor.
  static String reconstruirFragmentado(String texto) {
    var t = semAcentos(texto)
        .toLowerCase()
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\u00A0', ' ');
    t = t.replaceAll(RegExp(r'\s*/\s*'), '/');
    t = t.replaceAll(RegExp(r'\s*,\s*'), ',');
    t = t.replaceAll(RegExp(r'\s*\.\s*'), '.');
    return limparEspacos(t);
  }

  static List<Lancamento> lerComprasFallback(String texto) {
    final t = reconstruirFragmentado(texto);
    final inicio = t.indexOf('lancamentos: compras e saques');
    if (inicio < 0) return [];
    final fim = t.indexOf('lancamentos no cartao', inicio);
    if (fim <= inicio) return [];

    final secao = t.substring(inicio, fim);
    final datas = RegExp(r'\d{2}/\d{2}').allMatches(secao)
        .where((m) => dataValida(m.group(0)!))
        .toList();
    final resultado = <Lancamento>[];

    for (var i = 0; i < datas.length; i++) {
      final dm = datas[i];
      final fimBloco =
          i + 1 < datas.length ? datas[i + 1].start : secao.length;
      var bloco = secao.substring(dm.end, fimBloco);

      // Exige que o bloco tenha um valor monetário plausível.
      final valores = RegExp(r'-?\d[\d\.]*,\d{2}').allMatches(bloco).toList();
      if (valores.isEmpty) continue;
      final vm = valores.last;
      final valor = moedaParaDouble(vm.group(0)!);
      if (valor.abs() > 50000) continue;

      var antes = limparEspacos(bloco.substring(0, vm.start));
      int? pa;
      int? pt;
      final parcelas = RegExp(r'(\d{1,2})/(\d{1,2})\s*$').firstMatch(antes);
      if (parcelas != null) {
        final a = int.tryParse(parcelas.group(1)!);
        final b = int.tryParse(parcelas.group(2)!);
        if (a != null && b != null && a >= 1 && b >= a && b <= 60) {
          pa = a;
          pt = b;
          antes = limparEspacos(antes.substring(0, parcelas.start));
        }
      }
      if (antes.isEmpty || compactar(antes).startsWith('pagamento')) continue;

      resultado.add(
        Lancamento(
          data: dm.group(0)!,
          descricao: antes,
          categoria: 'outros',
          valor: valor,
          parcelaAtual: pa,
          totalParcelas: pt,
          tipo: pa != null && pt != null ? 'Parcelada' : 'À vista',
          observacoes: 'Parser v4 - fallback',
        ),
      );
    }
    return resultado;
  }

  static List<Lancamento> lerCompras(String texto, double? totalCartao) {
    final porLinhas = lerComprasPorLinhas(texto);
    final fallback = lerComprasFallback(texto);

    if (totalCartao == null) {
      return porLinhas.length >= fallback.length ? porLinhas : fallback;
    }

    double erro(List<Lancamento> l) =>
        (totalCartao - l.fold<double>(0, (s, e) => s + e.valor)).abs();

    if (porLinhas.isNotEmpty && erro(porLinhas) < 0.02) return porLinhas;
    if (fallback.isNotEmpty && erro(fallback) < 0.02) return fallback;
    if (porLinhas.isEmpty) return fallback;
    if (fallback.isEmpty) return porLinhas;
    return erro(porLinhas) <= erro(fallback) ? porLinhas : fallback;
  }

  static List<Lancamento> lerInternacional(String texto) {
    final resultado = <Lancamento>[];

    final transacoes = procurarSubtotal(
      texto,
      const [
        'Total transações inter. em R\$',
        'Total transacoes inter. em R\$',
      ],
    );
    final iof = procurarSubtotal(
      texto,
      const ['Repasse de IOF em R\$', 'Repasse de IOF'],
    );

    if (transacoes != null && transacoes.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Transações internacionais',
          categoria: 'internacional',
          valor: transacoes,
          tipo: 'Internacional',
          observacoes: 'Subtotal informado pelo Itaú',
        ),
      );
    }
    if (iof != null && iof.abs() > 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Repasse de IOF - transações internacionais',
          categoria: 'encargos',
          valor: iof,
          tipo: 'Encargo / IOF',
          observacoes: 'IOF informado pelo Itaú',
        ),
      );
    }
    return resultado;
  }

  static List<Lancamento> lerProdutosServicos(
    String texto,
    double? totalServicos,
  ) {
    final linhas = texto.replaceAll('\r', '').split('\n');
    final itens = <Lancamento>[];
    bool dentro = false;
    final rx = RegExp(
      r'^\s*(\d{2}/\d{2})\s+(.+?)\s+(-?[\d\.]+,\d{2})\s*$',
      caseSensitive: false,
    );

    for (final original in linhas) {
      final linha = limparEspacos(original);
      final c = compactar(linha);

      if (c.contains('lancamentos:produtoseservicos') ||
          c.contains('lancamentosprodutoseservicos')) {
        dentro = true;
        continue;
      }
      if (!dentro) continue;
      if (c.contains('totaldoslancamentosatuais')) break;

      final m = rx.firstMatch(linha);
      if (m == null || !dataValida(m.group(1)!)) continue;
      final desc = limparEspacos(m.group(2)!);
      final valor = moedaParaDouble(m.group(3)!);
      if (desc.isEmpty || valor.abs() > 50000) continue;

      itens.add(
        Lancamento(
          data: m.group(1)!,
          descricao: desc,
          categoria: 'produtos e serviços',
          valor: valor,
          tipo: 'Produto/Serviço',
          observacoes: 'Parser v4 - item de produtos/serviços',
        ),
      );
    }

    final soma = itens.fold<double>(0, (s, e) => s + e.valor);
    if (totalServicos != null && (totalServicos - soma).abs() < 0.02) {
      return itens;
    }

    // Se a leitura individual ficou incompleta, usa o subtotal oficial
    // para não inventar itens nem comprometer a conciliação.
    if (totalServicos != null && totalServicos.abs() > 0.001) {
      return [
        Lancamento(
          data: '',
          descricao: 'Subtotal produtos e serviços',
          categoria: 'produtos e serviços',
          valor: totalServicos,
          tipo: 'Produto/Serviço',
          observacoes:
              'Subtotal oficial usado porque os itens individuais não fecharam',
        ),
      ];
    }
    return itens;
  }

  static List<Lancamento> lerEncargos(String texto) {
    final total = procurarSubtotal(
      texto,
      const ['Total de encargos em R\$', 'Total de encargos em R$'],
    );
    if (total == null || total.abs() < 0.001) return [];
    return [
      Lancamento(
        data: '',
        descricao: 'Encargos cobrados nesta fatura',
        categoria: 'encargos',
        valor: total,
        tipo: 'Encargo financeiro',
        observacoes: 'Total de encargos informado pelo Itaú',
      ),
    ];
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
    final encargos = lerEncargos(texto);

    final lancamentos = <Lancamento>[
      ...compras,
      ...internacional,
      ...produtos,
      ...encargos,
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
        final extrator = PdfTextExtractor(documento);

        // O Itaú usa tabelas em duas colunas. Em alguns PDFs, a extração
        // comum devolve praticamente um caractere por linha e mistura as
        // duas colunas. O modo layoutText preserva melhor a posição visual.
        final textoBruto = extrator.extractText();
        final textoLayout = extrator.extractText(layoutText: true);

        documento.dispose();

        final resultadoLayout = ParserItau.processar(textoLayout);
        final resultadoBruto = ParserItau.processar(textoBruto);

        // Escolhe automaticamente a leitura que melhor reconstruiu a fatura.
        // Prioridade:
        // 1) fatura conciliada;
        // 2) menor diferença no subtotal do cartão;
        // 3) maior quantidade de compras individuais.
        ResultadoFatura melhorResultado(
          ResultadoFatura a,
          ResultadoFatura b,
        ) {
          if (a.conciliada != b.conciliada) {
            return a.conciliada ? a : b;
          }

          final erroA = a.diferencaCartao?.abs() ?? double.infinity;
          final erroB = b.diferencaCartao?.abs() ?? double.infinity;

          if ((erroA - erroB).abs() > 0.01) {
            return erroA < erroB ? a : b;
          }

          if (a.compras.length != b.compras.length) {
            return a.compras.length > b.compras.length ? a : b;
          }

          final erroGeralA = a.diferenca?.abs() ?? double.infinity;
          final erroGeralB = b.diferenca?.abs() ?? double.infinity;
          return erroGeralA <= erroGeralB ? a : b;
        }

        final resultado = melhorResultado(resultadoLayout, resultadoBruto);

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: resultado,
            // Mantemos os dois formatos no diagnóstico para facilitar
            // qualquer ajuste futuro sem perder a extração original.
            textoBruto:
                '===== TEXTO COM LAYOUT =====\n'
                '$textoLayout\n\n'
                '===== TEXTO BRUTO =====\n'
                '$textoBruto',
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
    b.writeln('Parser: v4 - leitura por linhas + seções + encargos');
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
