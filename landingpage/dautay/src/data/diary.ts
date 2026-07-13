export interface DiaryPage {
  id: number;
  media: string;
  type: 'video' | 'image';
  date: string;
  title: string;
  paragraphs: string[];
  signature: string;
}

export const diaryPages: DiaryPage[] = [
  {
    id: 1,
    media: '/images/1JGLLQ2IE_8F6LTV.MP4',
    type: 'video',
    date: '16/01/2026',
    title: 'Tròn 1 tháng tuổi',
    paragraphs: [
      'Chào con gái bé bỏng của bố mẹ! 💕',
      'Video này quay lén lúc con mới tròn 1 tháng tuổi. Nhìn con ngọ nguậy, cái miệng chúm chím dễ thương xỉu luôn, bố mẹ chỉ muốn cắn cho một cái!',
      'Thời gian trôi nhanh quá, chúc Dâu Tây của bố mẹ luôn ngoan ngoãn, hay ăn chóng lớn nhé. Yêu con vô vàn. 🍓',
    ],
    signature: 'Ký tên: Ba & Mẹ.',
  },
  {
    id: 2,
    media: '/images/firstdate.webp',
    type: 'image',
    date: '16/12/2025',
    title: 'Ngày đầu tiên',
    paragraphs: [
      'Chào mừng con đến với thế giới này!',
      'Giây phút đầu tiên được bế con trên tay, bố mẹ đã khóc vì hạnh phúc. Con bé xíu, đỏ hỏn và đáng yêu vô cùng.',
      'Cảm ơn con vì đã đến với bố mẹ, biến thế giới của bố mẹ trở nên hoàn hảo hơn bao giờ hết. ❤️',
    ],
    signature: 'Ba & Mẹ.',
  },
  {
    id: 3,
    media: '/images/IMG_0448.webp',
    type: 'image',
    date: '16/01/2026',
    title: 'Đầy tháng con',
    paragraphs: [
      'Nhanh quá, mới đó mà thiên thần của bố mẹ đã tròn 1 tháng tuổi rồi.',
      'Hôm nay nhà mình làm lễ đầy tháng cho con. Con ngoan lắm, lơ ngơ nhìn mọi người vô cùng đáng yêu.',
      'Nụ cười mỉm của con sưởi ấm gia đình mình. Mong con gái luôn khỏe mạnh, hay ăn chóng lớn và một đời bình an nghen!',
    ],
    signature: 'Ba & Mẹ.',
  },
];
