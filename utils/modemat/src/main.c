#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <limits.h>
#include <errno.h>
#include <stdlib.h>
#include <getopt.h>
#include <termios.h>

static int set_interface_attribs (int fd, int speed, int parity)
{
	struct termios tty;
	if (tcgetattr (fd, &tty) != 0)
	{
		printf("error %d from tcgetattr\n", errno);
		return -1;
	}

	cfsetospeed (&tty, speed);
	cfsetispeed (&tty, speed);

	tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8;     // 8-bit chars
	// disable IGNBRK for mismatched speed tests; otherwise receive break
	// as \000 chars
	tty.c_iflag &= ~IGNBRK;         // disable break processing
	tty.c_lflag = 0;                // no signaling chars, no echo,
																	// no canonical processing
	tty.c_oflag = 0;                // no remapping, no delays
	tty.c_cc[VMIN]  = 0;            // read doesn't block
	tty.c_cc[VTIME] = 5;            // 0.5 seconds read timeout

	tty.c_iflag &= ~(IXON | IXOFF | IXANY); // shut off xon/xoff ctrl

	tty.c_cflag |= (CLOCAL | CREAD);// ignore modem controls,
																	// enable reading
	tty.c_cflag &= ~(PARENB | PARODD);      // shut off parity
	tty.c_cflag |= parity;
	tty.c_cflag &= ~CSTOPB;
	tty.c_cflag &= ~CRTSCTS;

	if (tcsetattr (fd, TCSANOW, &tty) != 0)
	{
		printf("error %d from tcsetattr\n", errno);
		return -1;
	}
	return 0;
}

static int set_blocking (int fd, int should_block)
{
	struct termios tty;
	memset (&tty, 0, sizeof tty);
	if (tcgetattr (fd, &tty) != 0)
	{
		printf("error %d from tggetattr\n", errno);
		return -1;
	}

	tty.c_cc[VMIN]  = should_block ? 1 : 0;
	tty.c_cc[VTIME] = 5;            // 0.5 seconds read timeout

	if (tcsetattr (fd, TCSANOW, &tty) != 0)
	{
		printf("error %d setting term attributes\n", errno);
		return -1;
	}

	return 0;
}

static void flush_input(int fd)
{
	int ret;
	char buffer[1024];
	while (1)
	{
		ret = read(fd, buffer, sizeof(buffer));
		if (ret <= 0)
			return;
	}
}

static int tty_open(const char *port, const char *baud)
{
	int baudrate_d;
	tcflag_t baudrate;
	int fd;

	baudrate_d = (int)strtol(baud, NULL, 10);
	switch (baudrate_d)
	{
		case 0: baudrate = B0; break;
		case 50: baudrate = B50; break;
		case 75: baudrate = B75; break;
		case 110: baudrate = B110; break;
		case 134: baudrate = B134; break;
		case 150: baudrate = B150; break;
		case 200: baudrate = B200; break;
		case 300: baudrate = B300; break;
		case 600: baudrate = B600; break;
		case 1200: baudrate = B1200; break;
		case 1800: baudrate = B1800; break;
		case 2400: baudrate = B2400; break;
		case 4800: baudrate = B4800; break;
		case 9600: baudrate = B9600; break;
		case 19200: baudrate = B19200; break;
		case 38400: baudrate = B38400; break;
		case 57600: baudrate = B57600; break;
		case 115200: baudrate = B115200; break;
		case 230400: baudrate = B230400; break;
		case 460800: baudrate = B460800; break;
		case 921600: baudrate = B921600; break;
		default: return -1;
	}

	fd = open (port, O_RDWR | O_NOCTTY | O_SYNC);
	if (fd < 0)
	{
		printf("error %d opening %s\n", errno, port);
		return -1;
	}

	set_interface_attribs(fd, baudrate, 0);
	set_blocking(fd, 0);

	flush_input(fd);

	return fd;
}

/*
static void dump(char *name, uint8_t *ptr, size_t len)
{
  printf("%s", name);
  while(len)
  {
    printf("%02x ", *ptr);
    
    ptr++;
    len--;
  }
  printf("\n");
}
*/

int main (int argc, char **argv)
{
	int             option_index = 0;
	int             c;
	const char    * short_opt = "p:c:r:b:t:s:";
	struct option   long_opt[] =
	{
		{"help",          no_argument,            NULL, 0},
		{"port",          required_argument,      NULL, 0},
		{"command",       required_argument,      NULL, 0},
		{"response",      required_argument,      NULL, 0},
		{"baud",          required_argument,      NULL, 0},
		{"timeout",       required_argument,      NULL, 0},
		{"skiprn",        no_argument,            NULL, 0},
		{NULL,            0,                      NULL, 0}
	};

	int help_opt = 0;

	int has_port = 0;
	const char *port = NULL;
	size_t port_len = 0;

	int has_cmd = 0;
	const char *cmd = NULL;
	size_t cmd_len = 0;

	int has_response = 0;
	const char *response = NULL;
	size_t response_len = 0;

	int has_baud = 0;
	const char *baud = NULL;
	size_t baud_len = 0;
	
	int has_timeout = 0;
	const char *timeout = NULL;
	size_t timeout_len = 0;

	int has_skip_rn = 0;
	int skip_rn = 0;

	while((c = getopt_long(argc, argv, short_opt, long_opt, &option_index)) != -1)
	{
		//printf("%d(%c) : %s\n", c, c, optarg);
	#if 0
		if (option_index > 0)
			printf ("Parameter %s ", long_opt[option_index].name);
		if (optarg)
			printf ("argument %s", optarg);
		printf ("\n");
	#endif

		switch(c)
		{
			case -1:       /* no more arguments */
				break;

			case 0:
				if (option_index == 0) // help
				{
					help_opt = 1;
				}
				else if (option_index == 1) // port
				{
					has_port = 1;
					port = optarg;
					port_len = port ? strlen(port) : 0;
				}
				else if (option_index == 2) // command
				{
					has_cmd = 1;
					cmd = optarg;
					cmd_len = cmd ? strlen(cmd) : 0;
				}
				else if (option_index == 3) // response
				{
					has_response = 1;
					response = optarg;
					response_len = response ? strlen(response) : 0;
				}
				else if (option_index == 4) // baudrate
				{
					has_baud = 1;
					baud = optarg;
					baud_len = baud ? strlen(baud) : 0;
				}
				else if (option_index == 5) // baudrate
				{
					has_timeout = 1;
					timeout = optarg;
					timeout_len = timeout ? strlen(timeout) : 0;
				}
				else if (option_index == 6) // skiprn
				{
					has_skip_rn = skip_rn = 1;
				}
				break;

			case 'h':
				help_opt = 1;
				break;

			case 'p':
				has_port = 1;
				port = optarg;
				port_len = port ? strlen(port) : 0;
				break;
				
			case 'c':
				has_cmd = 1;
				cmd = optarg;
				cmd_len = cmd ? strlen(cmd) : 0;
				break;
				
			case 'r':
				has_response = 1;
				response = optarg;
				response_len = response ? strlen(response) : 0;
				break;
				
			case 'b':
				has_baud = 1;
				baud = optarg;
				baud_len = baud ? strlen(baud) : 0;
				break;
				
			case 't':
				has_timeout = 1;
				timeout = optarg;
				timeout_len = timeout ? strlen(timeout) : 0;
				break;
				
			case 's':
				has_skip_rn = skip_rn = 1;
				break;

			case ':':
			case '?':
				printf("Try `%s --help' for more information.\n", argv[0]);
				return -1;

			default:
				printf("%s: invalid option -- %c\n", argv[0], c);
				printf("Try `%s --help' for more information.\n", argv[0]);
				return -1;
		};
	};

	if (help_opt || !(has_port && has_cmd && has_response && has_baud) || (port_len == 0 || cmd_len == 0 || response_len == 0 || baud_len == 0))
	{
		printf("Usage: %s [OPTIONS]\n", argv[0]);
		printf("  -h, --help                help\n");
		printf("  -p, --port                modem tty port\n");
		printf("  -b, --baud                modem tty port baudrate\n");
		printf("  -c, --command             request (AT)\n");
		printf("  -r, --response            response (AT;OK)\n");
		printf("  -t, --timeout             timeout, ms (default 2000 ms)\n");
		printf("\n");

		return 1;
	}

	int ok;
	int i;
	int fd;
	int ret;
	int timeout_ms = 2000;
	int passed;
	char req_buffer[1024];
	size_t req_size;
	char res_buffer[1024];
	size_t res_size;
	char *ptr;

	#define RESPONSE_MSG_CNT        10
	#define RESPONSE_MSG_MAX_LEN    64

	char response_messages[RESPONSE_MSG_CNT][RESPONSE_MSG_MAX_LEN];
	size_t response_messages_cnt;

	if (cmd_len > sizeof(req_buffer)-3)
	{
		return -1;
	}
	
	if (has_timeout && timeout_len > 0) {
		timeout_ms = strtol(timeout, NULL, 10);
	}

	memset(req_buffer, 0x00, sizeof(req_buffer));
	memset(res_buffer, 0x00, sizeof(res_buffer));

	ok = 0;

	{
		size_t len;
		const char *sub, *next;
		
		memset(response_messages, 0x00, sizeof(response_messages));
		response_messages_cnt = 0;
		
		sub = response;
		next = strstr(response, ";");
		if (next)
		{
			//printf("More then one response: %s\n", response);
			
			while (next != NULL)
			{
				len = next - sub;
				if (len < (RESPONSE_MSG_MAX_LEN))
				{
					memcpy(response_messages[response_messages_cnt], sub, len);
					//printf("Add awaiting response: %s\n", response_messages[response_messages_cnt]);
					response_messages_cnt++;
					if (response_messages_cnt >= RESPONSE_MSG_CNT)
						break;
				}
				else
				{
					printf("More then one response: too long response\n");
					return -1;
				}
				
				next++;
				sub = next;
				next = strstr(next, ";");
			}
			
			len = strlen(sub);
			if (len > 0 && response_messages_cnt < RESPONSE_MSG_CNT)
			{
				strcpy(response_messages[response_messages_cnt], sub);
				response_messages_cnt++;
				
				//printf("Add awaiting response: %s\n", response_messages[response_messages_cnt]);
			}
		}
		else
		{
			//printf("Only one response: %s\n", response);

			if (response_len < (RESPONSE_MSG_MAX_LEN))
			{
				response_messages_cnt = 1;
				strcpy(response_messages[0], response);
			}
			else
			{
				printf("One response: too long response\n");
				return -1;
			}
		}
	}

	printf("Try to open %s...\n", port);
	fd = tty_open(port, baud);
	if (fd < 0)
	{
		return -1;
	}

	memcpy(req_buffer, cmd, cmd_len);
	req_size = cmd_len;

	if (!skip_rn)
	{
		req_buffer[req_size++] = '\r';
		req_buffer[req_size++] = '\n';
	}

	int tries;
	for (tries = 0; tries < 3; tries++)
	{
		memset(res_buffer, 0x00, sizeof(res_buffer));
		res_size = 0;

		ret = write(fd, req_buffer, req_size);
		if (ret < 0 || ret != (int)req_size)
		{
			close(fd);
			return -1;
		}
		
		memset(res_buffer, 0x00, sizeof(res_buffer));
		res_size = 0;
		
		passed = 0;
		while (1)
		{
			ret = read(fd, res_buffer + res_size, (sizeof(res_buffer) - 3) - res_size);
			//printf("read (%d)\n", ret);
			if (ret <= 0)
			{
				passed += 500; // in ms
				if (passed >= timeout_ms)
				{
					printf("tty port read timeout (%d/%d)\n", passed, timeout_ms);
					break;
				}
			}
			else
			{
				res_size += ret;
				
				ptr = strstr(res_buffer, req_buffer);
				if (ptr)
				{
					memmove(ptr, ptr + req_size, res_size - req_size);
					res_size -= req_size;
					res_buffer[res_size] = 0;
				}
				
				ptr = strstr(res_buffer, "ERROR");
				if (ptr)
				{
					printf("Error response\n");
					break;
				}
				
				for (i = 0; i < (int)response_messages_cnt; i++)
				{
					ptr = strstr(res_buffer, response_messages[i]);
					if (ptr != NULL)
					{
						ok = 1;
						goto exit;
					}
				}
			}
		}
	}

	exit:
	printf("%s\n", ok ? "ok" : "failed");
	if (!ok)
	{
		printf("Response: <<<%s>>>\n", res_buffer);
	}

	close(fd);
	return ok ? 0 : -1;
}
