package club.peacefulvanilla.protectionstonestestvault;

import net.milkbowl.vault.economy.AbstractEconomy;
import net.milkbowl.vault.economy.Economy;
import net.milkbowl.vault.economy.EconomyResponse;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.plugin.ServicePriority;
import org.bukkit.plugin.java.JavaPlugin;

import java.text.DecimalFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class TestVaultPlugin extends JavaPlugin {
    private final TestEconomy economy = new TestEconomy();

    @Override
    public void onEnable() {
        getServer().getServicesManager().register(
                Economy.class,
                economy,
                this,
                ServicePriority.Highest
        );
    }

    @Override
    public void onDisable() {
        getServer().getServicesManager().unregisterAll(this);
        economy.clear();
    }

    @Override
    public boolean onCommand(
            CommandSender sender,
            Command command,
            String label,
            String[] args
    ) {
        if (args.length == 1 && args[0].equalsIgnoreCase("reset")) {
            economy.clear();
            sender.sendMessage("TESTVAULT RESET");
            return true;
        }
        if (args.length == 2 && args[0].equalsIgnoreCase("balance")) {
            sender.sendMessage(
                    "TESTVAULT BALANCE player=" + args[1]
                            + " balance=" + economy.format(economy.getBalance(args[1]))
            );
            return true;
        }
        if (args.length == 3 && args[0].equalsIgnoreCase("set")) {
            try {
                double amount = Double.parseDouble(args[2]);
                if (amount < 0 || !Double.isFinite(amount)) {
                    throw new NumberFormatException();
                }
                economy.setBalance(args[1], amount);
                sender.sendMessage(
                        "TESTVAULT SET player=" + args[1]
                                + " balance=" + economy.format(amount)
                );
            } catch (NumberFormatException exception) {
                sender.sendMessage("TESTVAULT FAIL invalid-balance");
            }
            return true;
        }

        sender.sendMessage("TESTVAULT FAIL usage");
        return true;
    }

    private static final class TestEconomy extends AbstractEconomy {
        private static final DecimalFormat MONEY = new DecimalFormat("0.00");
        private final Map<String, Double> balances = new ConcurrentHashMap<>();

        @Override
        public boolean isEnabled() {
            return true;
        }

        @Override
        public String getName() {
            return "ProtectionStonesTestEconomy";
        }

        @Override
        public boolean hasBankSupport() {
            return false;
        }

        @Override
        public int fractionalDigits() {
            return 2;
        }

        @Override
        public String format(double amount) {
            return MONEY.format(amount);
        }

        @Override
        public String currencyNamePlural() {
            return "credits";
        }

        @Override
        public String currencyNameSingular() {
            return "credit";
        }

        @Override
        public boolean hasAccount(String playerName) {
            return balances.containsKey(key(playerName));
        }

        @Override
        public boolean hasAccount(String playerName, String worldName) {
            return hasAccount(playerName);
        }

        @Override
        public double getBalance(String playerName) {
            return balances.getOrDefault(key(playerName), 0.0);
        }

        @Override
        public double getBalance(String playerName, String worldName) {
            return getBalance(playerName);
        }

        @Override
        public boolean has(String playerName, double amount) {
            return amount >= 0 && getBalance(playerName) >= amount;
        }

        @Override
        public boolean has(String playerName, String worldName, double amount) {
            return has(playerName, amount);
        }

        @Override
        public EconomyResponse withdrawPlayer(String playerName, double amount) {
            if (amount < 0 || !Double.isFinite(amount)) {
                return failure(playerName, "Invalid amount");
            }
            synchronized (balances) {
                double balance = getBalance(playerName);
                if (balance < amount) {
                    return failure(playerName, "Insufficient funds");
                }
                double updated = balance - amount;
                balances.put(key(playerName), updated);
                return success(amount, updated);
            }
        }

        @Override
        public EconomyResponse withdrawPlayer(
                String playerName,
                String worldName,
                double amount
        ) {
            return withdrawPlayer(playerName, amount);
        }

        @Override
        public EconomyResponse depositPlayer(String playerName, double amount) {
            if (amount < 0 || !Double.isFinite(amount)) {
                return failure(playerName, "Invalid amount");
            }
            synchronized (balances) {
                double updated = getBalance(playerName) + amount;
                balances.put(key(playerName), updated);
                return success(amount, updated);
            }
        }

        @Override
        public EconomyResponse depositPlayer(
                String playerName,
                String worldName,
                double amount
        ) {
            return depositPlayer(playerName, amount);
        }

        @Override
        public EconomyResponse createBank(String name, String player) {
            return notImplemented();
        }

        @Override
        public EconomyResponse deleteBank(String name) {
            return notImplemented();
        }

        @Override
        public EconomyResponse bankBalance(String name) {
            return notImplemented();
        }

        @Override
        public EconomyResponse bankHas(String name, double amount) {
            return notImplemented();
        }

        @Override
        public EconomyResponse bankWithdraw(String name, double amount) {
            return notImplemented();
        }

        @Override
        public EconomyResponse bankDeposit(String name, double amount) {
            return notImplemented();
        }

        @Override
        public EconomyResponse isBankOwner(String name, String playerName) {
            return notImplemented();
        }

        @Override
        public EconomyResponse isBankMember(String name, String playerName) {
            return notImplemented();
        }

        @Override
        public List<String> getBanks() {
            return List.of();
        }

        @Override
        public boolean createPlayerAccount(String playerName) {
            balances.putIfAbsent(key(playerName), 0.0);
            return true;
        }

        @Override
        public boolean createPlayerAccount(String playerName, String worldName) {
            return createPlayerAccount(playerName);
        }

        void setBalance(String playerName, double amount) {
            balances.put(key(playerName), amount);
        }

        void clear() {
            balances.clear();
        }

        private EconomyResponse failure(String playerName, String message) {
            return new EconomyResponse(
                    0,
                    getBalance(playerName),
                    EconomyResponse.ResponseType.FAILURE,
                    message
            );
        }

        private EconomyResponse success(double amount, double balance) {
            return new EconomyResponse(
                    amount,
                    balance,
                    EconomyResponse.ResponseType.SUCCESS,
                    ""
            );
        }

        private EconomyResponse notImplemented() {
            return new EconomyResponse(
                    0,
                    0,
                    EconomyResponse.ResponseType.NOT_IMPLEMENTED,
                    "Banks are not supported by the local test economy"
            );
        }

        private String key(String playerName) {
            return playerName.toLowerCase(Locale.ROOT);
        }
    }
}
