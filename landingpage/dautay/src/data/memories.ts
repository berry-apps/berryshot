export interface Memory {
  id: string;
  date: string;
  caption: string;
  rotation: number;
  gradient: string;
  image?: string;
}

export const memories: Memory[] = [
  {
    id: '1',
    date: '16/12/2025',
    caption: 'Ngày đầu tiên gặp mặt bố mẹ',
    rotation: -3,
    gradient: 'bg-gradient-to-br from-[#FDE6E6] to-[#E8F3E4]',
    image: '/images/firstdate.webp',
  },
  {
    id: '2',
    date: '20/12/2025',
    caption: 'Được chụp ảnh 4 ngày sau sinh',
    rotation: 2,
    gradient: 'bg-gradient-to-br from-[#FFF0D4] to-[#FDE6E6]',
    image: '/images/IMG_3787.webp',
  },
  {
    id: '3',
    date: '20/12/2025',
    caption: 'Được BV PSHN chụp ảnh',
    rotation: 2,
    gradient: 'bg-gradient-to-br from-[#FFF0D4] to-[#FDE6E6]',
    image: '/images/IMG_3786.webp',
  },
  {
    id: '4',
    date: '16/01/2026',
    caption: 'Ngày con đầy tháng',
    rotation: -1,
    gradient: 'bg-gradient-to-br from-[#E8F3E4] to-[#D4E8E1]',
    image: '/images/IMG_0448.webp',
  },
  {
    id: '5',
    date: '16/02/2026',
    caption: 'Tròn 2 tháng tuổi, biết hóng chuyện rồi',
    rotation: 4,
    gradient: 'bg-gradient-to-br from-[#FDE6E6] to-[#FAD4D4]',
    image: '/images/IMG_3958.webp',
  },
  {
    id: '6',
    date: '16/03/2026',
    caption: 'Con tròn 3 tháng tuổi',
    rotation: -2,
    gradient: 'bg-gradient-to-br from-[#F3E8F3] to-[#FDE6E6]',
    image: '/images/IMG_4187.webp',
  },
];
