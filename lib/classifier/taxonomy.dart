/// 内置学科分类体系。
///
/// 每个叶子分类带有中英文关键词，分类器根据论文标题、摘要、关键词
/// 与这些词的匹配程度打分。ID 固定，保证多设备同步时不会产生重复分类。
/// 用户可以在应用里修改关键词或新增自己的分类。
class SeedCategory {
  final String id;
  final String name;
  final String? parentId;
  final List<String> keywords;
  const SeedCategory(this.id, this.name, this.parentId, [this.keywords = const []]);
}

const List<SeedCategory> seedCategories = [
  // ---------------- 计算机科学 ----------------
  SeedCategory('cs', '计算机科学', null),
  SeedCategory('cs.ml', '机器学习', 'cs', [
    'machine learning', 'deep learning', 'neural network', 'reinforcement learning',
    'supervised learning', 'unsupervised learning', 'self-supervised', 'representation learning',
    'gradient descent', 'optimization', 'transfer learning', 'meta-learning', 'federated learning',
    'generative model', 'diffusion model', 'variational autoencoder', 'gan', 'transformer',
    'graph neural network', 'contrastive learning', 'overfitting', 'regularization',
    '机器学习', '深度学习', '神经网络', '强化学习', '监督学习', '无监督学习', '自监督',
    '表示学习', '迁移学习', '联邦学习', '生成模型', '扩散模型', '图神经网络', '对比学习',
  ]),
  SeedCategory('cs.cv', '计算机视觉', 'cs', [
    'computer vision', 'image classification', 'object detection', 'semantic segmentation',
    'instance segmentation', 'image segmentation', 'convolutional neural network', 'cnn',
    'image generation', 'super-resolution', 'pose estimation', 'optical flow', 'visual tracking',
    'point cloud', '3d reconstruction', 'nerf', 'gaussian splatting', 'video understanding',
    'face recognition', 'image', 'visual', 'pixel',
    '计算机视觉', '图像分类', '目标检测', '语义分割', '实例分割', '图像分割', '卷积神经网络',
    '图像生成', '超分辨率', '姿态估计', '光流', '目标跟踪', '点云', '三维重建', '人脸识别', '图像', '视觉',
  ]),
  SeedCategory('cs.cl', '自然语言处理', 'cs', [
    'natural language processing', 'nlp', 'language model', 'large language model', 'llm',
    'machine translation', 'question answering', 'text classification', 'sentiment analysis',
    'named entity recognition', 'dialogue', 'summarization', 'tokenization', 'word embedding',
    'bert', 'gpt', 'prompt', 'in-context learning', 'instruction tuning', 'retrieval-augmented',
    'speech recognition', 'corpus', 'text', 'linguistic',
    '自然语言处理', '语言模型', '大语言模型', '大模型', '机器翻译', '问答', '文本分类',
    '情感分析', '命名实体识别', '对话系统', '文本摘要', '词向量', '提示学习', '语音识别', '语料', '文本',
  ]),
  SeedCategory('cs.sys', '系统与网络', 'cs', [
    'operating system', 'distributed system', 'cloud computing', 'edge computing', 'database',
    'storage system', 'file system', 'compiler', 'scheduling', 'gpu', 'parallel computing',
    'high performance computing', 'network protocol', 'wireless network', 'software-defined networking',
    'internet of things', 'iot', 'latency', 'throughput', 'microservice', 'serverless',
    '操作系统', '分布式系统', '云计算', '边缘计算', '数据库', '存储系统', '编译器', '调度',
    '并行计算', '高性能计算', '网络协议', '无线网络', '软件定义网络', '物联网', '时延', '吞吐',
  ]),
  SeedCategory('cs.se', '软件工程', 'cs', [
    'software engineering', 'program analysis', 'software testing', 'fuzzing', 'code generation',
    'program synthesis', 'static analysis', 'bug detection', 'refactoring', 'formal verification',
    'programming language', 'type system', 'code review', 'open source',
    '软件工程', '程序分析', '软件测试', '模糊测试', '代码生成', '程序合成', '静态分析',
    '缺陷检测', '形式化验证', '编程语言', '类型系统',
  ]),
  SeedCategory('cs.cr', '信息安全', 'cs', [
    'security', 'privacy', 'cryptography', 'encryption', 'attack', 'adversarial', 'malware',
    'intrusion detection', 'blockchain', 'authentication', 'differential privacy', 'vulnerability',
    'side channel', 'backdoor', 'homomorphic',
    '信息安全', '网络安全', '隐私', '密码学', '加密', '攻击', '对抗样本', '恶意软件',
    '入侵检测', '区块链', '身份认证', '差分隐私', '漏洞', '侧信道', '后门',
  ]),
  SeedCategory('cs.hci', '人机交互', 'cs', [
    'human-computer interaction', 'hci', 'user study', 'user interface', 'usability',
    'virtual reality', 'augmented reality', 'visualization', 'interaction design', 'accessibility',
    '人机交互', '用户研究', '用户界面', '可用性', '虚拟现实', '增强现实', '可视化', '交互设计',
  ]),
  SeedCategory('cs.ro', '机器人', 'cs', [
    'robot', 'robotics', 'manipulation', 'grasping', 'motion planning', 'slam', 'navigation',
    'autonomous driving', 'self-driving', 'locomotion', 'embodied', 'uav', 'drone',
    '机器人', '机械臂', '抓取', '运动规划', '路径规划', '同步定位与建图', '导航', '自动驾驶',
    '无人驾驶', '具身智能', '无人机',
  ]),
  SeedCategory('cs.theory', '算法与理论', 'cs', [
    'algorithm', 'complexity', 'np-hard', 'approximation algorithm', 'graph theory',
    'combinatorial optimization', 'computational complexity', 'data structure', 'lower bound',
    'quantum computing', 'quantum algorithm',
    '算法', '复杂度', '近似算法', '图论', '组合优化', '计算复杂性', '数据结构', '量子计算',
  ]),

  // ---------------- 数学 ----------------
  SeedCategory('math', '数学', null),
  SeedCategory('math.pure', '基础数学', 'math', [
    'theorem', 'lemma', 'proof', 'algebra', 'topology', 'manifold', 'number theory',
    'geometry', 'group theory', 'category theory', 'homology', 'riemannian', 'banach space',
    'hilbert space', 'functional analysis', 'conjecture',
    '定理', '引理', '证明', '代数', '拓扑', '流形', '数论', '几何', '群论', '同调', '泛函分析', '猜想',
  ]),
  SeedCategory('math.applied', '应用数学与统计', 'math', [
    'statistics', 'statistical', 'bayesian', 'stochastic', 'probability', 'regression',
    'hypothesis testing', 'monte carlo', 'numerical method', 'finite element',
    'partial differential equation', 'pde', 'ordinary differential equation', 'convex optimization',
    'time series', 'estimator', 'inference',
    '统计', '贝叶斯', '随机过程', '概率', '回归', '假设检验', '蒙特卡洛', '数值方法', '有限元',
    '偏微分方程', '常微分方程', '凸优化', '时间序列', '估计量',
  ]),

  // ---------------- 物理学 ----------------
  SeedCategory('phys', '物理学', null),
  SeedCategory('phys.cond', '凝聚态物理', 'phys', [
    'condensed matter', 'superconductivity', 'superconductor', 'topological insulator',
    'magnetism', 'spin', 'phonon', 'band structure', 'lattice', 'graphene', 'quantum hall',
    'density functional theory', 'dft', 'electron correlation',
    '凝聚态', '超导', '拓扑绝缘体', '磁性', '自旋', '声子', '能带', '晶格', '石墨烯', '密度泛函',
  ]),
  SeedCategory('phys.quant', '量子与光学', 'phys', [
    'quantum', 'entanglement', 'qubit', 'quantum information', 'photon', 'laser', 'optics',
    'optical', 'photonic', 'metamaterial', 'nonlinear optics', 'spectroscopy', 'cold atom',
    '量子', '纠缠', '量子比特', '量子信息', '光子', '激光', '光学', '超材料', '非线性光学', '光谱', '冷原子',
  ]),
  SeedCategory('phys.hep', '粒子与核物理', 'phys', [
    'particle physics', 'hadron', 'quark', 'higgs', 'standard model', 'neutrino', 'collider',
    'lhc', 'nuclear physics', 'dark matter', 'gauge theory', 'string theory',
    '粒子物理', '强子', '夸克', '希格斯', '标准模型', '中微子', '对撞机', '核物理', '暗物质', '规范场', '弦论',
  ]),
  SeedCategory('phys.astro', '天文与天体物理', 'phys', [
    'astrophysics', 'galaxy', 'galaxies', 'cosmology', 'black hole', 'gravitational wave',
    'star', 'stellar', 'exoplanet', 'supernova', 'telescope', 'cosmic', 'redshift',
    '天体物理', '星系', '宇宙学', '黑洞', '引力波', '恒星', '系外行星', '超新星', '望远镜', '红移',
  ]),

  // ---------------- 化学与材料 ----------------
  SeedCategory('chem', '化学', null),
  SeedCategory('chem.general', '化学', 'chem', [
    'chemistry', 'chemical', 'synthesis', 'catalyst', 'catalysis', 'reaction', 'molecule',
    'molecular', 'organic', 'inorganic', 'polymer', 'electrochemistry', 'electrochemical',
    'spectroscopy', 'crystal', 'ligand', 'oxidation', 'reduction', 'solvent',
    '化学', '合成', '催化', '催化剂', '反应', '分子', '有机', '无机', '聚合物', '高分子',
    '电化学', '晶体', '配体', '氧化', '还原', '溶剂',
  ]),
  SeedCategory('mat', '材料科学', null),
  SeedCategory('mat.general', '材料科学', 'mat', [
    'materials', 'material', 'nanomaterial', 'nanoparticle', 'thin film', 'alloy', 'composite',
    'ceramic', 'battery', 'lithium', 'perovskite', 'semiconductor', 'microstructure',
    'mechanical properties', 'corrosion', 'coating', '2d material',
    '材料', '纳米材料', '纳米颗粒', '薄膜', '合金', '复合材料', '陶瓷', '电池', '锂离子',
    '钙钛矿', '半导体', '微观结构', '力学性能', '腐蚀', '涂层', '二维材料',
  ]),

  // ---------------- 生命科学与医学 ----------------
  SeedCategory('bio', '生物学', null),
  SeedCategory('bio.mol', '分子与细胞生物学', 'bio', [
    'gene', 'genome', 'genomic', 'protein', 'cell', 'cellular', 'dna', 'rna', 'mrna',
    'transcription', 'crispr', 'sequencing', 'mutation', 'enzyme', 'metabolism', 'expression',
    'single-cell', 'stem cell', 'bioinformatics', 'protein structure',
    '基因', '基因组', '蛋白质', '细胞', '转录', '测序', '突变', '酶', '代谢', '表达',
    '单细胞', '干细胞', '生物信息',
  ]),
  SeedCategory('bio.eco', '生态与进化', 'bio', [
    'ecology', 'ecosystem', 'evolution', 'evolutionary', 'species', 'biodiversity',
    'population', 'phylogenetic', 'habitat', 'conservation',
    '生态', '生态系统', '进化', '演化', '物种', '生物多样性', '种群', '系统发育', '栖息地', '保护',
  ]),
  SeedCategory('bio.neuro', '神经科学', 'bio', [
    'neuroscience', 'neuron', 'neural circuit', 'brain', 'cortex', 'cognitive', 'fmri',
    'eeg', 'synapse', 'hippocampus', 'brain-computer interface',
    '神经科学', '神经元', '神经环路', '大脑', '皮层', '认知', '脑电', '突触', '海马', '脑机接口',
  ]),
  SeedCategory('med', '医学', null),
  SeedCategory('med.clinical', '临床医学', 'med', [
    'clinical', 'patient', 'patients', 'disease', 'diagnosis', 'treatment', 'therapy', 'cancer',
    'tumor', 'randomized controlled trial', 'cohort', 'surgery', 'mortality', 'hospital',
    'prognosis', 'drug', 'clinical trial', 'covid-19', 'infection',
    '临床', '患者', '疾病', '诊断', '治疗', '疗法', '癌症', '肿瘤', '随机对照', '队列',
    '手术', '死亡率', '医院', '预后', '药物', '感染',
  ]),
  SeedCategory('med.imaging', '医学影像与健康信息', 'med', [
    'medical imaging', 'medical image', 'mri', 'ct scan', 'computed tomography', 'x-ray',
    'ultrasound', 'radiology', 'pathology', 'electronic health record', 'ehr', 'healthcare',
    '医学影像', '医学图像', '磁共振', '超声', '放射', '病理', '电子病历', '医疗',
  ]),
  SeedCategory('med.public', '公共卫生与药学', 'med', [
    'public health', 'epidemiology', 'epidemic', 'pandemic', 'vaccine', 'pharmacology',
    'pharmaceutical', 'nutrition', 'mental health',
    '公共卫生', '流行病学', '疫情', '疫苗', '药理', '药学', '营养', '心理健康',
  ]),

  // ---------------- 工程 ----------------
  SeedCategory('eng', '工程技术', null),
  SeedCategory('eng.ee', '电子与通信工程', 'eng', [
    'circuit', 'signal processing', 'antenna', 'wireless communication', '5g', '6g', 'mimo',
    'channel estimation', 'beamforming', 'modulation', 'radar', 'sensor', 'power electronics',
    'integrated circuit', 'vlsi', 'fpga', 'transistor',
    '电路', '信号处理', '天线', '无线通信', '信道估计', '波束成形', '调制', '雷达', '传感器',
    '电力电子', '集成电路', '晶体管',
  ]),
  SeedCategory('eng.control', '控制与自动化', 'eng', [
    'control', 'controller', 'control system', 'model predictive control', 'pid', 'stability',
    'lyapunov', 'feedback', 'state estimation', 'kalman filter', 'fault diagnosis', 'power system',
    'smart grid',
    '控制', '控制器', '控制系统', '模型预测控制', '稳定性', '李雅普诺夫', '反馈', '状态估计',
    '卡尔曼滤波', '故障诊断', '电力系统', '智能电网',
  ]),
  SeedCategory('eng.mech', '机械与航空航天', 'eng', [
    'mechanical', 'fluid dynamics', 'turbulence', 'heat transfer', 'aerodynamic', 'aircraft',
    'spacecraft', 'vibration', 'manufacturing', 'additive manufacturing', 'finite element analysis',
    'combustion', 'engine',
    '机械', '流体力学', '湍流', '传热', '空气动力', '飞行器', '航天器', '振动', '制造', '增材制造', '燃烧', '发动机',
  ]),
  SeedCategory('eng.civil', '土木与建筑', 'eng', [
    'civil engineering', 'structural', 'concrete', 'bridge', 'building', 'seismic',
    'geotechnical', 'transportation', 'traffic', 'urban planning', 'architecture',
    '土木', '结构', '混凝土', '桥梁', '建筑', '抗震', '岩土', '交通', '城市规划',
  ]),
  SeedCategory('eng.energy', '能源与环境工程', 'eng', [
    'energy', 'renewable', 'solar cell', 'photovoltaic', 'wind power', 'hydrogen', 'fuel cell',
    'carbon emission', 'carbon capture', 'wastewater', 'pollution', 'pollutant',
    '能源', '可再生', '太阳能电池', '光伏', '风电', '氢能', '燃料电池', '碳排放', '碳捕集', '废水', '污染',
  ]),

  // ---------------- 地球与环境 ----------------
  SeedCategory('earth', '地球与环境科学', null),
  SeedCategory('earth.general', '地球与环境科学', 'earth', [
    'climate', 'climate change', 'atmosphere', 'atmospheric', 'ocean', 'precipitation',
    'remote sensing', 'geology', 'earthquake', 'soil', 'hydrology', 'glacier', 'land use',
    'environmental', 'satellite',
    '气候', '气候变化', '大气', '海洋', '降水', '遥感', '地质', '地震', '土壤', '水文', '冰川', '土地利用', '环境',
  ]),
  SeedCategory('agri', '农学', null),
  SeedCategory('agri.general', '农学', 'agri', [
    'agriculture', 'agricultural', 'crop', 'yield', 'plant', 'rice', 'wheat', 'maize',
    'livestock', 'fertilizer', 'irrigation', 'food security',
    '农业', '作物', '产量', '植物', '水稻', '小麦', '玉米', '畜牧', '肥料', '灌溉', '粮食安全',
  ]),

  // ---------------- 人文社科 ----------------
  SeedCategory('econ', '经济与管理', null),
  SeedCategory('econ.econ', '经济学', 'econ', [
    'economics', 'economic', 'market', 'monetary policy', 'inflation', 'gdp', 'labor market',
    'trade', 'fiscal', 'econometrics', 'price', 'firm', 'investment', 'finance', 'financial',
    'stock', 'asset pricing', 'bank',
    '经济', '市场', '货币政策', '通货膨胀', '劳动力', '贸易', '财政', '计量经济', '价格',
    '企业', '投资', '金融', '股票', '资产定价', '银行',
  ]),
  SeedCategory('econ.mgmt', '管理学', 'econ', [
    'management', 'organization', 'organizational', 'strategy', 'supply chain', 'operations research',
    'marketing', 'consumer', 'innovation', 'entrepreneurship', 'leadership', 'corporate governance',
    '管理', '组织', '战略', '供应链', '运筹', '营销', '消费者', '创新', '创业', '领导力', '公司治理',
  ]),
  SeedCategory('soc', '社会科学', null),
  SeedCategory('soc.psy', '心理学', 'soc', [
    'psychology', 'psychological', 'behavior', 'behavioral', 'emotion', 'personality',
    'cognition', 'anxiety', 'depression', 'participants', 'survey',
    '心理', '行为', '情绪', '人格', '焦虑', '抑郁', '被试', '问卷',
  ]),
  SeedCategory('soc.soc', '社会学与政治学', 'soc', [
    'sociology', 'social', 'society', 'policy', 'political', 'government', 'governance',
    'inequality', 'migration', 'gender', 'public opinion', 'election',
    '社会', '社会学', '政策', '政治', '政府', '治理', '不平等', '移民', '性别', '舆论', '选举',
  ]),
  SeedCategory('soc.edu', '教育学', 'soc', [
    'education', 'educational', 'student', 'students', 'teacher', 'teaching', 'learning outcome',
    'curriculum', 'classroom', 'pedagogy', 'higher education',
    '教育', '学生', '教师', '教学', '课程', '课堂', '高等教育',
  ]),
  SeedCategory('soc.law', '法学', 'soc', [
    'law', 'legal', 'court', 'regulation', 'legislation', 'constitution', 'contract', 'rights',
    '法律', '法学', '法院', '监管', '立法', '宪法', '合同', '权利',
  ]),
  SeedCategory('hum', '人文学科', null),
  SeedCategory('hum.general', '语言、文学、历史与哲学', 'hum', [
    'linguistics', 'literature', 'literary', 'history', 'historical', 'philosophy',
    'philosophical', 'ethics', 'culture', 'cultural', 'art', 'religion',
    '语言学', '文学', '历史', '哲学', '伦理', '文化', '艺术', '宗教',
  ]),
];

/// 没有匹配到任何学科时使用的分类。
const String uncategorizedId = 'uncategorized';
