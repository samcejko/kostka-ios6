/*
 * Copyright (c) 2026 samcejko. Part of Kostka (BSD license, as lwjgl/README.md says).
 */
package kostka.awt;

import java.awt.AWTException;
import java.awt.Button;
import java.awt.Canvas;
import java.awt.Checkbox;
import java.awt.CheckboxMenuItem;
import java.awt.Choice;
import java.awt.Desktop;
import java.awt.Dialog;
import java.awt.FileDialog;
import java.awt.Font;
import java.awt.Frame;
import java.awt.GraphicsDevice;
import java.awt.HeadlessException;
import java.awt.Label;
import java.awt.Menu;
import java.awt.MenuBar;
import java.awt.MenuItem;
import java.awt.Panel;
import java.awt.PopupMenu;
import java.awt.PrintJob;
import java.awt.Robot;
import java.awt.ScrollPane;
import java.awt.Scrollbar;
import java.awt.SystemTray;
import java.awt.TextArea;
import java.awt.TextField;
import java.awt.TrayIcon;
import java.awt.Window;
import java.awt.datatransfer.Clipboard;
import java.awt.dnd.DragGestureEvent;
import java.awt.dnd.InvalidDnDOperationException;
import java.awt.dnd.peer.DragSourceContextPeer;
import java.awt.font.TextAttribute;
import java.awt.im.InputMethodHighlight;
import java.awt.im.spi.InputMethodDescriptor;
import java.awt.image.ColorModel;
import java.awt.peer.ButtonPeer;
import java.awt.peer.CanvasPeer;
import java.awt.peer.CheckboxMenuItemPeer;
import java.awt.peer.CheckboxPeer;
import java.awt.peer.ChoicePeer;
import java.awt.peer.DesktopPeer;
import java.awt.peer.DialogPeer;
import java.awt.peer.FileDialogPeer;
import java.awt.peer.FontPeer;
import java.awt.peer.FramePeer;
import java.awt.peer.KeyboardFocusManagerPeer;
import java.awt.peer.LabelPeer;
import java.awt.peer.ListPeer;
import java.awt.peer.MenuBarPeer;
import java.awt.peer.MenuItemPeer;
import java.awt.peer.MenuPeer;
import java.awt.peer.PanelPeer;
import java.awt.peer.PopupMenuPeer;
import java.awt.peer.RobotPeer;
import java.awt.peer.ScrollPanePeer;
import java.awt.peer.ScrollbarPeer;
import java.awt.peer.SystemTrayPeer;
import java.awt.peer.TextAreaPeer;
import java.awt.peer.TextFieldPeer;
import java.awt.peer.TrayIconPeer;
import java.awt.peer.WindowPeer;
import java.util.Map;
import java.util.Properties;

import sun.awt.LightweightFrame;
import sun.awt.SunToolkit;

/**
 * Kostka's AWT on iOS: windows that exist without being drawn. Old Minecraft (Classic to 1.5.2) opens a Frame with
 * an Applet and a Canvas, and hands the Canvas to LWJGL, which on iOS shows the game in its own view anyway; these
 * peers give the frame, the applet and the canvas what AWT asks of them (a size, a place, being displayable) and
 * nothing more. Pictures are drawn by KGraphics, in Java. Widgets (buttons, text areas) do not exist.
 *
 * Chosen with -Dawt.toolkit=kostka.awt.KToolkit -Djava.awt.graphicsenv=kostka.awt.KGraphicsEnvironment and
 * -Djava.awt.headless=false; the screen's size from -Dkostka.screen.width / -Dkostka.screen.height.
 */
public class KToolkit extends SunToolkit {
	private final KFocusPeer focus = new KFocusPeer();
	private final Clipboard clipboard = new Clipboard("System");

	static int screenWidth() {
		return Integer.getInteger("kostka.screen.width", 1024).intValue();
	}

	static int screenHeight() {
		return Integer.getInteger("kostka.screen.height", 768).intValue();
	}

	private static HeadlessException none(String what) {
		return new HeadlessException(what + " does not exist on iOS (Kostka's AWT has windows, not widgets)");
	}

	/* Windows and the containers in them */

	public WindowPeer createWindow(Window target) {
		return new KWindowPeer(target);
	}

	public FramePeer createFrame(Frame target) {
		return new KWindowPeer(target);
	}

	public FramePeer createLightweightFrame(LightweightFrame target) {
		return new KWindowPeer(target);
	}

	public DialogPeer createDialog(Dialog target) {
		return new KWindowPeer(target);
	}

	public CanvasPeer createCanvas(Canvas target) {
		return new KComponentPeer(target);
	}

	public PanelPeer createPanel(Panel target) {
		return new KComponentPeer(target);
	}

	/* Widgets: none */

	public ButtonPeer createButton(Button target) {
		throw none("A button");
	}

	public TextFieldPeer createTextField(TextField target) {
		throw none("A text field");
	}

	public ChoicePeer createChoice(Choice target) {
		throw none("A choice");
	}

	public LabelPeer createLabel(Label target) {
		throw none("A label");
	}

	public ListPeer createList(java.awt.List target) {
		throw none("A list");
	}

	public CheckboxPeer createCheckbox(Checkbox target) {
		throw none("A check box");
	}

	public ScrollbarPeer createScrollbar(Scrollbar target) {
		throw none("A scroll bar");
	}

	public ScrollPanePeer createScrollPane(ScrollPane target) {
		throw none("A scroll pane");
	}

	public TextAreaPeer createTextArea(TextArea target) {
		throw none("A text area");
	}

	public FileDialogPeer createFileDialog(FileDialog target) {
		throw none("A file dialog");
	}

	public MenuBarPeer createMenuBar(MenuBar target) {
		throw none("A menu bar");
	}

	public MenuPeer createMenu(Menu target) {
		throw none("A menu");
	}

	public PopupMenuPeer createPopupMenu(PopupMenu target) {
		throw none("A pop-up menu");
	}

	public MenuItemPeer createMenuItem(MenuItem target) {
		throw none("A menu item");
	}

	public CheckboxMenuItemPeer createCheckboxMenuItem(CheckboxMenuItem target) {
		throw none("A menu item");
	}

	public DragSourceContextPeer createDragSourceContextPeer(DragGestureEvent dge) {
		throw new InvalidDnDOperationException("No drag and drop on iOS");
	}

	public TrayIconPeer createTrayIcon(TrayIcon target) throws AWTException {
		throw new AWTException("No system tray on iOS");
	}

	public SystemTrayPeer createSystemTray(SystemTray target) {
		return null;
	}

	public boolean isTraySupported() {
		return false;
	}

	public FontPeer getFontPeer(String name, int style) {
		return null;
	}

	public RobotPeer createRobot(Robot target, GraphicsDevice screen) throws AWTException {
		return new KPointer.Robot();
	}

	private final java.awt.peer.MouseInfoPeer mouseInfo = new KPointer.Info();

	public synchronized java.awt.peer.MouseInfoPeer getMouseInfoPeer() {
		return mouseInfo;
	}

	public KeyboardFocusManagerPeer getKeyboardFocusManagerPeer() {
		return focus;
	}

	protected DesktopPeer createDesktopPeer(Desktop target) {
		throw none("The desktop");
	}

	public boolean isDesktopSupported() {
		return false;
	}

	/* The screen */

	protected int getScreenWidth() {
		return screenWidth();
	}

	protected int getScreenHeight() {
		return screenHeight();
	}

	public int getScreenResolution() {
		return 132;   // (the iPad's)
	}

	public ColorModel getColorModel() {
		return ColorModel.getRGBdefault();
	}

	protected boolean syncNativeQueue(long timeout) {
		return false;
	}

	public void sync() {
	}

	public void grab(Window w) {
	}

	public void ungrab(Window w) {
	}

	/* The rest */

	public PrintJob getPrintJob(Frame frame, String jobtitle, Properties props) {
		return null;
	}

	public void beep() {
	}

	// (Toolkit's own version asks the default toolkit, itself: every real toolkit answers it)
	public boolean areExtraMouseButtonsEnabled() {
		return false;
	}

	public Clipboard getSystemClipboard() {
		// (within the game: what it copies, it can paste)
		return clipboard;
	}

	public Map<TextAttribute, ?> mapInputMethodHighlight(InputMethodHighlight highlight) {
		return null;
	}

	public sun.awt.datatransfer.DataTransferer getDataTransferer() {
		return null;
	}

	public InputMethodDescriptor getInputMethodAdapterDescriptor() throws AWTException {
		return null;
	}

	public boolean isModalityTypeSupported(Dialog.ModalityType modalityType) {
		return false;
	}

	public boolean isModalExclusionTypeSupported(Dialog.ModalExclusionType modalExclusionType) {
		return false;
	}
}
