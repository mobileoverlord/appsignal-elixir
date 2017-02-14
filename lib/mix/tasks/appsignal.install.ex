defmodule Mix.Tasks.Appsignal.Install do
  use Mix.Task
  alias Appsignal.Utils.PushApiKeyValidator

  def run([]) do
    header()
    IO.puts "We're missing an AppSignal Push API key and cannot continue."
    IO.puts "Please supply one as an argument to this command.\n"
    IO.puts "  mix appsignal.install push_api_key\n"
    IO.puts "You can find your push_api_key on https://appsignal.com/accounts under 'Add app'"
    IO.puts "Contact us at support@appsignal.com if you're stuck."
  end

  def run([push_api_key]) do
    config = %{active: true, push_api_key: push_api_key}
    Application.put_env(:appsignal, :config, config)
    Appsignal.Config.initialize

    header()
    validate_push_api_key()
    config = Map.put(config, :name, ask_for_app_name())
    case ask_kind_of_configuration() do
      :file ->
        write_config_file(config)
        link_config_file()
        activate_config_for_env("dev")
        activate_config_for_env("stag")
        activate_config_for_env("prod")
      :env ->
        output_config_environment_variables(config)
    end

    IO.puts "\nAppSignal installed! 🎉"
  end

  defp header do
    IO.puts "AppSignal install"
    IO.puts String.duplicate("=", 80)
    IO.puts "Website:       https://appsignal.com"
    IO.puts "Documentation: http://docs.appsignal.com"
    IO.puts "Support:       support@appsignal.com"
    IO.puts String.duplicate("=", 80)
    IO.puts "\nWelcome to AppSignal!\n"
    IO.puts "This installer will guide you through setting up AppSignal in your application."
    IO.puts "We will perform some checks on your system, ask how you like AppSignal to be "
    IO.puts "configured and for what environments.\n"
    IO.puts String.duplicate("=", 80)
    IO.puts ""
  end

  defp validate_push_api_key do
    IO.write "Validating Push API key: "
    case PushApiKeyValidator.validate(Application.get_env(:appsignal, :config)) do
      :ok -> IO.puts "Valid! 🎉"
      :invalid ->
        IO.puts "Invalid"
        IO.puts "  Please make sure you're using the correct push api key from appsignal.com"
        IO.puts "  Contact us at support@appsignal.com if you're stuck."
        exit :shutdown
      {:error, reason} ->
        IO.puts reason
        exit :shutdown
    end
  end

  defp ask_for_app_name, do: ask_for_input("What is your application's name?")

  defp ask_kind_of_configuration do
    IO.puts "\nThere are two methods of configuring AppSignal in your application."
    IO.puts "  Option 1: Using a \"config/appsignal.exs\" file. (1)"
    IO.puts "  Option 2: Using system environment variables.  (2)"
    case ask_for_input("What is your preferred configuration method? (1/2)") do
      "1" -> :file
      "2" -> :env
      _ ->
        IO.puts "I'm sorry, I didn't quite get that."
        ask_kind_of_configuration()
    end
  end

  defp output_config_environment_variables(config) do
    IO.puts "Configuring with environment variables."
    IO.puts "Please put the following variables in your environment to configure AppSignal.\n"
    IO.puts ~s(  export APPSIGNAL_APP_NAME="#{config[:name]}")
    IO.puts ~s(  export APPSIGNAL_PUSH_API_KEY="#{config[:push_api_key]}")
  end

  defp write_config_file(config) do
    IO.write "Writing config file config/appsignal.exs: "

    case File.open appsignal_config_file_path(), [:write] do
      {:ok, file} ->
        case IO.binwrite(file, appsignal_config_file_contents(config)) do
          :ok -> IO.puts "Success!"
          {:error, reason} ->
            IO.puts "Failure! #{reason}"
            exit :shutdown
        end
        File.close(file)
      {:error, reason} ->
        IO.puts "Failure! #{reason}"
        exit :shutdown
    end
  end

  # Link the config/appsignal.exs config file to the config/config.exs file.
  # If already linked, it's ignored.
  defp link_config_file do
    IO.write "Linking config to config/config.exs: "

    config_file = Path.join("config", "config.exs")
    IO.write "Linking config to config/config.exs: "
    active_content = "\nimport_config \"#{appsignal_config_filename()}\"\n"
    if appsignal_config_linked?() do
      IO.puts "Success! (Already linked?)"
    else
      case append_to_file(config_file, active_content) do
        :ok -> IO.puts "Success!"
        {:error, reason} ->
          IO.puts "Failure! #{reason}"
          exit :shutdown
      end
    end
  end

  defp config_file_path, do: Path.join("config", "config.exs")
  defp appsignal_config_filename, do: "appsignal.exs"
  defp appsignal_config_file_path, do: Path.join("config", appsignal_config_filename())

  # Checks if AppSignal was already linked in the main config/config.exs file.
  defp appsignal_config_linked? do
    case File.read(config_file_path()) do
      {:ok, contents} ->
        String.contains?(contents, ~s(import_config "#{appsignal_config_filename()})) ||
          String.contains?(contents, "import_config '#{appsignal_config_filename()}")
      {:error, reason} ->
        IO.puts "Failure! #{reason}"
        exit :shutdown
    end
  end

  # Contents for the config/appsignal.exs file.
  defp appsignal_config_file_contents(config) do
    "use Mix.Config\n\n" <>
      "config :appsignal, :config,\n" <>
      ~s(  name: "#{config[:name]}",\n) <>
      ~s(  push_api_key: "#{config[:push_api_key]}"\n)
  end

  # Append a line to Mix configuration environment files which activate
  # AppSignal. This is done for development, staging and production
  # environments if they are present.
  defp activate_config_for_env(config) do
    config_file = Path.join("config", "#{config}.exs")
    if File.exists? config_file do
      IO.write "Activating #{config} environment: "

      active_content = "\nconfig :appsignal, :config, active: true\n"
      case file_contains?(config_file, active_content) do
        :ok -> IO.puts "Success! (Already active?)"
        {:error, :not_found} ->
          case append_to_file(config_file, active_content) do
            :ok -> IO.puts "Success!"
            {:error, reason} ->
              IO.puts "Failure! #{reason}"
              exit :shutdown
          end
        {:error, reason} ->
          IO.puts "Failure! #{reason}"
          exit :shutdown
      end
    end
  end

  defp file_contains?(path, contents) do
    case File.read(path) do
      {:ok, file_contents} ->
        case String.contains?(file_contents, contents) do
          true -> :ok
          _ -> {:error, :not_found}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_to_file(path, contents) do
    case File.open path, [:append] do
      {:ok, file} ->
        result = IO.binwrite(file, contents)
        File.close(file)
        result
      {:error, reason} -> {:error, reason}
    end
  end

  defp ask_for_input(prompt) do
    input = String.trim(IO.gets("#{prompt}: "))
    if String.length(input) <= 0 do
      IO.puts "I'm sorry, I didn't quite get that."
      ask_for_input(prompt)
    else
      input
    end
  end
end