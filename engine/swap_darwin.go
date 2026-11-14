//go:build darwin

package main

import "golang.org/x/sys/unix"

// swapPaths 는 두 폴더의 자리를 '한 번에' 바꿔요 (macOS renamex_np RENAME_SWAP).
// 응용 프로그램 폴더의 DayROAD.app 이 한순간도 없어지지 않아서, 맥이 위젯을 '지워진 앱의 위젯'으로 보고
// 바탕화면에서 치우는 일이 없어요. 같은 디스크가 아니면 오류를 돌려줘요 (그때는 예전 방식으로 옮겨요).
func swapPaths(a, b string) error { return unix.RenamexNp(a, b, unix.RENAME_SWAP) }
