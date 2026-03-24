import { View, StyleSheet } from "react-native";
import { ThemedText } from "@/components/themed-text";

export default function HomeScreen() {
  return (
    <View style={styles.container}>
      <ThemedText type="title">Home</ThemedText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
  },
});