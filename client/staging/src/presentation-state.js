export class PresentationState {
    loading = true;
    mode = 'GAME';
    muted = false;
    focused = document.hasFocus();
    visible = document.visibilityState === 'visible';
    setMode(value) {
        if (value === 'GAME' || value === 'MENU' || value === 'AUTOMAP' || value === 'INTERMISSION') {
            this.mode = value;
        }
    }
}
