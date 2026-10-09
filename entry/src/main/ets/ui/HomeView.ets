import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { CoursesView } from './CoursesView';
import { NoticesView } from './NoticesView';
import { MineView } from './MineView';
import { Course } from '../data/Models';

@ComponentV2
export struct HomeView {
  @Param selectedTabIndex: number = 0;
  @Event onTabChange: (index: number) => void = () => {};
  @Event onRequestLogin: () => void = () => {};
  @Event onOpenCourse: (course: Course) => void = () => {};

  private tabSymbol(normal: Resource, selected: Resource): TabBarSymbol {
    return {
      normal: new SymbolGlyphModifier(normal),
      selected: new SymbolGlyphModifier(selected),
    };
  }

  build() {
    HdsTabs({ barPosition: BarPosition.End, index: this.selectedTabIndex }) {
      TabContent() {
        CoursesView({ onRequestLogin: () => { this.onRequestLogin(); },
          onOpenCourse: (course: Course) => { this.onOpenCourse(course); } })
      }.tabBar(BottomTabBarStyle.of(
        this.tabSymbol($r('sys.symbol.book_pages'), $r('sys.symbol.book_pages_fill')),
        $r('app.string.tab_courses')))
      TabContent() {
        NoticesView()
      }.tabBar(BottomTabBarStyle.of(
        this.tabSymbol($r('sys.symbol.bell'), $r('sys.symbol.bell_fill')),
        $r('app.string.tab_notices')))
      TabContent() {
        MineView({ onRequestLogin: () => { this.onRequestLogin(); } })
      }.tabBar(BottomTabBarStyle.of(
        this.tabSymbol($r('sys.symbol.person'), $r('sys.symbol.person_fill')),
        $r('app.string.tab_mine')))
    }
    .scrollable(false)
    .vertical(false)
    .barOverlap(true)
    .barFloatingStyle({
      barBottomMargin: 28,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .expandSafeArea([], [])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .onChange((index: number) => { this.onTabChange(index); })
    .width('100%').height(LayoutPolicy.matchParent)
  }
}
