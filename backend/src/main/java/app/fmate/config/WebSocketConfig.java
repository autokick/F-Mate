package app.fmate.config;

import app.fmate.chat.ChatSocketHandler;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {

    private final ChatSocketHandler chat;

    public WebSocketConfig(ChatSocketHandler chat) {
        this.chat = chat;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        // 모바일 앱은 Origin 헤더가 없거나 임의값이므로 출처 제한 대신 첫 메시지 토큰 인증으로 보호한다
        registry.addHandler(chat, "/ws/chat").setAllowedOriginPatterns("*");
    }
}
