package com.laxce.adl.ui.theme.screen

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.animation.core.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.geometry.Offset
import com.laxce.adl.R


@Composable
fun AnimatedGradientText(blueLength: Float = 500f) {
    val transition = rememberInfiniteTransition()
    val animatedOffset by transition.animateFloat(
        initialValue = -blueLength,
        targetValue = 800f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 10000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        )
    )

    val gradientColors = listOf(Color(0xFF00AC00), Color(0xFF39B3FE), Color(0xFF00AC00))

    val startOffset = Offset(x = animatedOffset, y = 0f)
    val endOffset = Offset(x = animatedOffset + blueLength, y = 0f)

    val animatedBrush = Brush.linearGradient(
        colors = gradientColors,
        start = startOffset,
        end = endOffset
    )

    Text(
        text = "COINCEEPER",
        style = TextStyle(
            fontSize = 48.sp,
            fontWeight = FontWeight.Black,
            brush = animatedBrush
        ),
        modifier = Modifier.padding(16.dp)
    )
}

@Composable
fun NextScreen(navController: NavController) {
    val context = LocalContext.current

    BackHandler(enabled = false) {
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(0.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(id = R.drawable.logo),
            contentDescription = "Wallet Icon",
            modifier = Modifier.size(300.dp)
        )

        AnimatedGradientText()

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = context.getString(R.string.import_wallet_description),
            style = TextStyle(
                fontSize = 16.sp,
                color = Color.Gray
            ),
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = { navController.navigate("importWallet") },
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.White,
                contentColor = Color(0xFF4C70D0)
            ),
            shape = RoundedCornerShape(50.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .height(50.dp)
                .border(1.dp, Color.Blue, RoundedCornerShape(50.dp))
        ) {
            Text(
                text = context.getString(R.string.import_wallet),
                fontSize = 18.sp,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = { navController.navigate("create-new-wallet") },
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(0xFF4C70D0),
                contentColor = Color.White
            ),
            shape = RoundedCornerShape(50.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .height(50.dp)
        ) {
            Text(
                text = context.getString(R.string.create_new_wallet),
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}
