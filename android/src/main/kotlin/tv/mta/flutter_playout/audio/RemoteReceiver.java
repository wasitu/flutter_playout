package tv.mta.flutter_playout.audio;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.view.KeyEvent;

public class RemoteReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {

        try {

            if (Intent.ACTION_MEDIA_BUTTON.equals(intent.getAction())) {

                final KeyEvent event = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);

                if (event != null && event.getAction() == KeyEvent.ACTION_DOWN) {

                    switch (event.getKeyCode()) {

                        case KeyEvent.KEYCODE_MEDIA_PAUSE:

                            AudioServiceBinder.service.pauseAudio();

                            break;

                        case KeyEvent.KEYCODE_MEDIA_PLAY:

                            AudioServiceBinder.service.resumeAudio();

                            break;
                        case KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD: {
                            int second = (AudioServiceBinder.service.getCurrentAudioPosition() - 10000)/1000;
                            if (second < 0) second = 0;
                            AudioServiceBinder.service.seekAudio(second);
                            break;
                        }
                        case KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD: {
                            int second = (AudioServiceBinder.service.getCurrentAudioPosition() + 10000)/1000;
                            int duration = AudioServiceBinder.service.getAudioPlayer().getDuration();
                            if (second > duration) second = second;
                            AudioServiceBinder.service.seekAudio(second);
                            break;
                        }
                    }
                }
            }

        } catch (Exception e) { /* ignore */ }
    }
}
